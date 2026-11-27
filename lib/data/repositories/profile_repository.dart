import 'dart:async';

import '../profile/personal_details.dart';
import '../profile/presence.dart';
import '../profile/status_text.dart';
import 'package:connectum/data/socket/socket.dart';

/// A status or presence command the server refused, or could not be sent.
/// [code] is the server's (`invalid_status`, `invalid_presence`,
/// `rate_limited`) or `offline` / `timeout` from here.
class ProfileCommandException implements Exception {
  const ProfileCommandException(this.code, [this.text = '']);

  final String code;
  final String text;

  @override
  String toString() => 'ProfileCommandException($code)';
}

/// The own profile: the status and presence commands and the private
/// details.
class ProfileRepository {
  ProfileRepository(
    this._socket, {
    this.ackTimeout = const Duration(seconds: 8),
  });

  final SocketService _socket;

  /// How long a command waits for its `ack` or `error`.
  final Duration ackTimeout;

  bool get isOnline => _socket.isOnline;

  /// `/setstatus <text>`; empty text sends a bare `/setstatus`, which clears
  /// the status. Returns when the server has acked.
  Future<void> setStatus(String text) {
    final clean = StatusText.toSend(text);
    return _command(
      'setstatus',
      clean.isEmpty ? '/setstatus' : '/setstatus $clean',
    );
  }

  /// `/setpresence <word>`. Returns when the server has acked.
  Future<void> setPresence(Presence presence) =>
      _command('setpresence', '/setpresence ${presence.wire}');

  Future<void> _command(String cmd, String line) async {
    if (!_socket.isOnline) throw const ProfileCommandException('offline');
    final done = Completer<void>()..future.ignore();
    final sub = _socket.events.listen((e) {
      if (e['cmd'] != cmd || done.isCompleted) return;
      if (e['type'] == 'ack' && e['ok'] == true) {
        done.complete();
      } else if (e['type'] == 'error') {
        done.completeError(
          ProfileCommandException(
            '${e['code'] ?? 'error'}',
            '${e['text'] ?? ''}',
          ),
        );
      }
    });
    try {
      final isSent = await _socket.sendCommand(line);
      if (!isSent) throw const ProfileCommandException('offline');
      await done.future.timeout(
        ackTimeout,
        onTimeout: () => throw const ProfileCommandException('timeout'),
      );
    } finally {
      await sub.cancel();
    }
  }

  /// `profile.get`: the private details, roles and designation.
  Future<ProfileRecord> loadRecord() async =>
      ProfileRecord.fromJson(await _socket.sdCall('profile.get', const {}));

  /// `profile.update` with [changes] (null values clear). Returns the record
  /// the server answers with.
  Future<ProfileRecord> updateDetails(Map<String, dynamic> changes) async =>
      ProfileRecord.fromJson(await _socket.sdCall('profile.update', changes));
}
