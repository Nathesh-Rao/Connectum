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
  EncryptionPolicy(this._socket, this._store, this._e2e);

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
  ///  - the peer has a device (optional or required): encrypt. If that cannot
  ///    be done (this phone not registered, a pinned key changed) the answer
  ///    is blocked, never plain.
  ///  - the peer has no device: plain only in optional mode on a thread with
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
  }) {
    if (mode == null) return const E2eSendDecision.unknown();
    if (mode == 'off') return const E2eSendDecision.plain();
    if (peerDevices.isEmpty) {
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
    if (kind == 'group') {
      final v = isLookup ? await verdict(convId, facts) : cached(convId, facts);
      return switch (v) {
        EncryptionVerdict.encrypted => const E2eSendDecision.blocked(
          "Can't send in encrypted groups from mobile yet",
        ),
        EncryptionVerdict.unknown => const E2eSendDecision.unknown(),
        EncryptionVerdict.plain => const E2eSendDecision.plain(),
      };
    }
    if (_mode == null) return const E2eSendDecision.unknown();
    if (_mode == 'off') return const E2eSendDecision.plain();
    final me = (_store.userId ?? '').toLowerCase();
    final peer = convId.substring(3).toLowerCase();
    var dirs = _e2e.cachedDevices([peer, me]);
    final keys = await _e2e.keys();
    Future<E2eSendDecision?> read({required bool isForced}) async {
      try {
        dirs = await _e2e.devicesOf([peer, me], isForced: isForced);
        return null;
      } on SocketCallError catch (_) {
        if (!_socket.isOnline) return const E2eSendDecision.unknown();
        return E2eSendDecision.blocked(
          E2eSendDecision.cantSend,
          reason: "couldn't check $peer's devices",
          isTransient: true,
        );
      }
    }

    if (dirs == null) {
      if (!isLookup) return const E2eSendDecision.unknown();
      final failed = await read(isForced: false);
      if (failed != null) return failed;
    }
    final isStale =
        isLookup &&
        keys != null &&
        (dirs![peer] ?? const []).isNotEmpty &&
        !(dirs![me] ?? const []).any((d) => d.id == keys.id);
    if (isStale) {
      // This phone may have registered after the directory was cached.
      final failed = await read(isForced: true);
      if (failed != null) return failed;
    }
    final found = dirs!;
    final peerDevices = found[peer] ?? const <E2eDevicePublic>[];
    return decide(
      mode: _mode,
      peer: peer,
      isEncryptedThread: facts.isE2e,
      peerDevices: peerDevices,
      myDevices: found[me] ?? const [],
      keys: keys,
      pinChanges: peerDevices.isEmpty
          ? const []
          : await _e2e.checkPins(found, isRecord: isLookup),
    );
  }

  Future<void> _loadMode({bool isOnlineRead = true}) async {
    final key = 'e2e.mode.${_store.orgId}';
    _mode ??= await _store.readValue(key);
    if (!isOnlineRead || _isModeFresh || !_socket.isOnline) return;
    try {
      final data = await _socket.sdCall('e2e.status', {});
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
              (e.value as List).isNotEmpty,
        );
      } else {
        final data = await _socket.sdCall('e2e.group_devices', {
          'group': convId.substring(6),
        });
        hasKeys = ((data['members'] as Map?) ?? {}).entries.any(
          (m) =>
              m.key.toString().toLowerCase() != me &&
              m.value is List &&
              (m.value as List).isNotEmpty,
        );
      }
      _peers[convId] = (hasKeys: hasKeys, at: DateTime.now());
    } on SocketCallError catch (_) {}
  }
}
