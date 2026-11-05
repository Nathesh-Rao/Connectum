import 'package:get/get.dart';

import '../e2e/e2e_models.dart';
import '../models/ids.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'e2e_repository.dart';

enum EncryptionVerdict { encrypted, plain, unknown }

class ThreadFacts {
  const ThreadFacts({required this.isE2e, required this.hasHistory});

  final bool isE2e;
  final bool hasHistory;
}

class EncryptionPolicy {
  EncryptionPolicy(this._socket, this._store, this._e2e) {
    // What was learned about threads and the mode belongs to one organisation.
    ever(_store.current, (_) {
      _mode = null;
      _isModeFresh = false;
      _peers.clear();
    });
  }

  static const _peerTtl = Duration(minutes: 5);

  final SocketService _socket;
  final SessionStore _store;
  final E2eRepository _e2e;

  String? _mode;
  bool _isModeFresh = false;
  final _peers = <String, ({bool hasKeys, DateTime at})>{};

  void onReconnected() => _isModeFresh = false;

  /// The single rule for "may a plain message be sent into this thread".
  ///
  /// Only direct messages and groups can be encrypted (global room, hosts,
  /// forms and AI never are). A thread counts as encrypted when:
  ///  - the conversation or one of its messages carries the server's `e2e`
  ///    flag (isE2e), or
  ///  - `e2e.status` reports mode `required`.
  /// In mode `optional` a thread that already has history is plain. Only a
  /// thread with no history asks whether a peer (DM) or any other member
  /// (group) has published device keys (`e2e.devices` / `e2e.group_devices`).
  /// It cannot detect: the mode while never connected (unknown, not blocked),
  /// revoked or stale keys (lookups are cached 5 minutes), or encrypted
  /// messages older than what has been loaded.
  EncryptionVerdict evaluate(String convId, ThreadFacts facts, bool? peerKeys) {
    final kind = convId.split(':').first;
    if (kind != 'dm' && kind != 'group') return EncryptionVerdict.plain;
    if (facts.isE2e || _mode == 'required') return EncryptionVerdict.encrypted;
    if (_mode == null) return EncryptionVerdict.unknown;
    if (_mode == 'off' || facts.hasHistory) return EncryptionVerdict.plain;
    if (peerKeys == null) return EncryptionVerdict.unknown;
    return peerKeys ? EncryptionVerdict.encrypted : EncryptionVerdict.plain;
  }

  /// Cached answer for the composer. `unknown` must not block typing.
  EncryptionVerdict cached(String convId, ThreadFacts facts) {
    final peer = _peers[convId];
    final fresh = peer != null && DateTime.now().difference(peer.at) < _peerTtl;
    return evaluate(convId, facts, fresh ? peer.hasKeys : null);
  }

  /// Looks things up when needed, used right before a send.
  Future<EncryptionVerdict> verdict(String convId, ThreadFacts facts) async {
    final kind = convId.split(':').first;
    if (kind != 'dm' && kind != 'group') return EncryptionVerdict.plain;
    if (facts.isE2e) return EncryptionVerdict.encrypted;
    await _loadMode();
    var verdict = cached(convId, facts);
    if (verdict == EncryptionVerdict.unknown && _mode == 'optional') {
      await _lookupPeer(convId);
      verdict = cached(convId, facts);
    }
    return verdict;
  }

  /// THE rule for a send into a direct message, used by the composer, by
  /// `sendText` and by the outbox flush. Nothing else decides whether text
  /// may leave the phone unencrypted: only a `plain` verdict does.
  ///  - mode off: plain.
  ///  - the peer has a device (optional or required): encrypt, wrapped for
  ///    every device in [peerDevices] and [myDevices], recovery keys included.
  ///    If that cannot be done (this phone not registered, a pinned key
  ///    changed) the answer is blocked, never plain.
  ///  - the peer has no device (a recovery key alone does not count): plain only in optional mode on a thread with
  ///    no encrypted history; otherwise blocked.
  ///  - mode not known yet: unknown (the send waits and asks again).
  static E2eSendDecision decide({
    required String? mode,
    required String peer,
    required bool isEncryptedThread,
    required List<E2eDevicePublic> peerDevices,
    required List<E2eDevicePublic> myDevices,
    required E2eDeviceKeys? keys,
    required List<E2ePinChange> pinChanges,
    bool isSettingUp = true,
  }) {
    if (mode == null) return const E2eSendDecision.unknown();
    if (mode == 'off') return const E2eSendDecision.plain();
    // The recovery key is wrapped for, but it is not a device that can read:
    // a peer with only that has not set up encryption.
    final hasPeerReader = E2eRepository.readers(peerDevices).isNotEmpty;
    // Not set up yet is never plain: in required mode, or whenever the peer
    // could be written to securely, the send waits for this phone's keys.
    if (keys == null && (mode == 'required' || hasPeerReader)) {
      return isSettingUp
          ? const E2eSendDecision.setupPending()
          : const E2eSendDecision.blocked(
              E2eSendDecision.cantSend,
              reason: E2eSendDecision.notSetUpReason,
            );
    }
    if (!hasPeerReader) {
      if (mode == 'required' || isEncryptedThread) {
        return E2eSendDecision.blocked("$peer hasn't set up encryption yet");
      }
      return const E2eSendDecision.plain();
    }
    if (keys == null || !myDevices.any((d) => d.id == keys.id)) {
      return const E2eSendDecision.blocked(
        E2eSendDecision.cantSend,
        reason: "this phone isn't registered for secure messaging",
      );
    }
    if (pinChanges.isNotEmpty) {
      final isPeer = pinChanges.any((c) => c.user == peer);
      return E2eSendDecision.blocked(
        isPeer
            ? "$peer's security key changed"
            : 'Your security key changed on another device',
        isKeyChange: true,
        keyChangeUser: peer,
      );
    }
    return E2eSendDecision.encrypt(
      recipients: [...peerDevices, ...myDevices],
      keys: keys,
    );
  }

  /// THE rule for a send into a group, the counterpart of [decide]. The
  /// server refuses an envelope when a member has no device
  /// (`e2e_peer_not_ready`) or a device has no box (`e2e_stale_devices`), so:
  ///  - mode off: plain.
  ///  - every other member has a reader device: encrypt, wrapped for all
  ///    devices of all members, mine included, recovery keys too. A changed
  ///    pinned key or an unregistered phone blocks, never plain.
  ///  - some member has no reader device: plain only in optional mode on a
  ///    thread with no encrypted history (what the web does in optional
  ///    mode); in required mode or an encrypted thread it is blocked and the
  ///    members are named.
  static E2eSendDecision decideGroup({
    required String? mode,
    required String me,
    required bool isEncryptedThread,
    required Map<String, List<E2eDevicePublic>> members,
    required E2eDeviceKeys? keys,
    required List<E2ePinChange> pinChanges,
    bool isSettingUp = true,
  }) {
    if (mode == null) return const E2eSendDecision.unknown();
    if (mode == 'off') return const E2eSendDecision.plain();
    final others = [
      for (final e in members.entries)
        if (e.key != me) e,
    ];
    final without = [
      for (final e in others)
        if (E2eRepository.readers(e.value).isEmpty) e.key,
    ]..sort();
    final hasReader = others.any(
      (e) => E2eRepository.readers(e.value).isNotEmpty,
    );
    if (keys == null && (mode == 'required' || hasReader)) {
      return isSettingUp
          ? const E2eSendDecision.setupPending()
          : const E2eSendDecision.blocked(
              E2eSendDecision.cantSend,
              reason: E2eSendDecision.notSetUpReason,
            );
    }
    if (without.isNotEmpty) {
      if (mode == 'required' || isEncryptedThread) {
        return E2eSendDecision.blocked(
          '${without.join(', ')} ${without.length == 1 ? "hasn't" : "haven't"} set up encryption yet',
        );
      }
      return const E2eSendDecision.plain();
    }
    final mine = members[me] ?? const <E2eDevicePublic>[];
    if (keys == null || !mine.any((d) => d.id == keys.id)) {
      return const E2eSendDecision.blocked(
        E2eSendDecision.cantSend,
        reason: "this phone isn't registered for secure messaging",
      );
    }
    if (pinChanges.isNotEmpty) {
      final who = pinChanges.first.user;
      return E2eSendDecision.blocked(
        who == me
            ? 'Your security key changed on another device'
            : "$who's security key changed",
        isKeyChange: true,
        keyChangeUser: who,
      );
    }
    final byId = {
      for (final devices in members.values)
        for (final d in devices) d.id: d,
    };
    if (byId.length > maxWraps) {
      return const E2eSendDecision.blocked(
        E2eSendDecision.cantSend,
        reason: 'this group has too many devices to encrypt for',
      );
    }
    return E2eSendDecision.encrypt(
      recipients: byId.values.toList(),
      keys: keys,
    );
  }

  /// The most boxes one envelope may carry.
  static const maxWraps = 250;

  /// Gathers what [decide] needs. With [isLookup] it may ask the server and
  /// pins first-seen keys (a send); without it, it reads caches only (the
  /// composer) and an unanswered question is `unknown`.
  Future<E2eSendDecision> decideSend(
    String convId,
    ThreadFacts facts, {
    bool isLookup = true,
  }) async {
    final kind = convId.split(':').first;
    if (kind != 'dm' && kind != 'group') return const E2eSendDecision.plain();
    await _loadMode(isOnlineRead: isLookup);
    if (kind == 'group') return _decideGroupSend(convId, facts, isLookup);
    if (_mode == null) return const E2eSendDecision.unknown();
    if (_mode == 'off') return const E2eSendDecision.plain();
    final me = (_store.userId ?? '').toLowerCase();
    final peer = convId.substring(3).toLowerCase();
    final keys = await _e2e.keys();
    if (keys == null && _mode == 'required') {
      return decide(
        mode: _mode,
        peer: peer,
        isEncryptedThread: facts.isE2e,
        peerDevices: const [],
        myDevices: const [],
        keys: null,
        pinChanges: const [],
        isSettingUp: _e2e.isSettingUp,
      );
    }
    // A send reuses a list younger than `sendListTtl`; the composer only
    // reads the cache. A stale refusal or a devices event drops the entry.
    var dirs = isLookup ? null : _e2e.cachedDevices([peer, me]);
    if (dirs == null) {
      if (!isLookup) return const E2eSendDecision.unknown();
      try {
        dirs = await _e2e.devicesOf([
          peer,
          me,
        ], maxAge: E2eRepository.sendListTtl);
      } on SocketCallError catch (_) {
        if (!_socket.isOnline) return const E2eSendDecision.unknown();
        return E2eSendDecision.blocked(
          E2eSendDecision.cantSend,
          reason: "couldn't check $peer's devices",
          isTransient: true,
        );
      }
    }
    final found = dirs;
    final peerDevices = found[peer] ?? const <E2eDevicePublic>[];
    return decide(
      mode: _mode,
      peer: peer,
      isEncryptedThread: facts.isE2e,
      peerDevices: peerDevices,
      myDevices: found[me] ?? const [],
      keys: keys,
      isSettingUp: _e2e.isSettingUp,
      pinChanges: peerDevices.isEmpty
          ? const []
          : await _e2e.checkPins(found, isRecord: isLookup),
    );
  }

  Future<E2eSendDecision> _decideGroupSend(
    String convId,
    ThreadFacts facts,
    bool isLookup,
  ) async {
    if (_mode == null) return const E2eSendDecision.unknown();
    if (_mode == 'off') return const E2eSendDecision.plain();
    final group = convId.substring(6);
    final me = (_store.userId ?? '').toLowerCase();
    final keys = await _e2e.keys();
    // A send asks the server for the member list right before it seals; the
    // cache serves only the composer.
    var members = isLookup ? null : _e2e.cachedGroupDevices(group);
    if (members == null) {
      if (!isLookup) {
        // Nothing cached: a thread that already holds encrypted history must
        // not read as open.
        return const E2eSendDecision.unknown();
      }
      try {
        members = await _e2e.groupDevices(group);
      } on SocketCallError catch (e) {
        if (!_socket.isOnline) return const E2eSendDecision.unknown();
        if (e.code == 'limit') {
          return const E2eSendDecision.blocked(
            E2eSendDecision.cantSend,
            reason: "groups of more than 200 people can't be encrypted yet",
          );
        }
        return const E2eSendDecision.blocked(
          E2eSendDecision.cantSend,
          reason: "couldn't check the members' devices",
          isTransient: true,
        );
      }
    }
    final changes = await _e2e.checkPins(members, isRecord: isLookup);
    return decideGroup(
      mode: _mode,
      me: me,
      isEncryptedThread: facts.isE2e,
      members: members,
      keys: keys,
      pinChanges: changes,
      isSettingUp: _e2e.isSettingUp,
    );
  }

  Future<void> _loadMode({bool isOnlineRead = true}) async {
    final key = 'e2e.mode.${_store.orgId}';
    _mode ??= await _store.readValue(key);
    if (!isOnlineRead || _isModeFresh || !_socket.isOnline) return;
    try {
      final data = await _socket.sdCall(
        'e2e.status',
        await _e2e.currentStatusArgs(),
      );
      final mode = idText(data['mode']);
      if (mode.isNotEmpty) {
        _mode = mode;
        _isModeFresh = true;
        await _store.writeValue(key, mode);
      }
    } on SocketCallError catch (_) {}
  }

  Future<void> _lookupPeer(String convId) async {
    if (!_socket.isOnline) return;
    final me = (_store.userId ?? '').toLowerCase();
    try {
      bool hasKeys;
      if (convId.startsWith('dm:')) {
        final peer = convId.substring(3);
        final data = await _socket.sdCall('e2e.devices', {
          'users': [peer],
        });
        final devices = (data['users'] as Map?) ?? {};
        hasKeys = devices.entries.any(
          (e) =>
              e.key.toString().toLowerCase() == peer.toLowerCase() &&
              e.value is List &&
              (e.value as List).any((d) => d is Map && d['recovery'] != true),
        );
      } else {
        final data = await _socket.sdCall('e2e.group_devices', {
          'group': convId.substring(6),
        });
        hasKeys = ((data['members'] as Map?) ?? {}).entries.any(
          (m) =>
              m.key.toString().toLowerCase() != me &&
              m.value is List &&
              (m.value as List).any((d) => d is Map && d['recovery'] != true),
        );
      }
      _peers[convId] = (hasKeys: hasKeys, at: DateTime.now());
    } on SocketCallError catch (_) {}
  }
}
