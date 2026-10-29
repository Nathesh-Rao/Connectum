import '../models/ids.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';

enum EncryptionVerdict { encrypted, plain, unknown }

class ThreadFacts {
  const ThreadFacts({required this.isE2e, required this.hasHistory});

  final bool isE2e;
  final bool hasHistory;
}

class EncryptionPolicy {
  EncryptionPolicy(this._socket, this._store);

  static const _peerTtl = Duration(minutes: 5);

  final SocketService _socket;
  final SessionStore _store;

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

  Future<void> _loadMode() async {
    final key = 'e2e.mode.${_store.orgId}';
    _mode ??= await _store.readValue(key);
    if (_isModeFresh || !_socket.isOnline) return;
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
