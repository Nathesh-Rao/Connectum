import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/models/session_info.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Session extends Fake implements SessionStore {
  @override
  final current = Rxn<SessionInfo>();
  @override
  String? get orgId => 'org';
  @override
  String? get userId => 'ann';
  @override
  bool get hasSession => false;
}

class _Connectivity extends Fake implements ConnectivityService {
  @override
  final hasNetwork = true.obs;
  @override
  final simulateOffline = false.obs;
}

class _Api extends Fake implements ApiClient {}

void main() {
  late SocketService socket;

  setUp(() {
    socket = SocketService(_Session(), _Connectivity(), _Api());
    socket.start();
  });

  for (final frame in const [
    '{"type":"sd_event","event":"session_expired","reason":"password_changed"}',
    '{"type":"sd_event","event":"session_ended"}',
    '{"type":"sd_event","event":"session_expired"}',
  ]) {
    test('$frame ends the session with no reconnect', () {
      socket.receiveForTest(frame);
      expect(socket.connection.value, SocketState.expired);
      expect(socket.isRetryScheduled, isFalse);
    });

    test('$frame: network regain, resume or a stray connect never retry', () {
      socket.receiveForTest(frame);
      socket.connectNow(resetBackoff: true);
      socket.connectNow();
      expect(socket.connection.value, SocketState.expired);
      expect(socket.isRetryScheduled, isFalse);
    });
  }

  test('a new sign-in (start) clears the ended state', () {
    socket.receiveForTest(
      '{"type":"sd_event","event":"session_expired","reason":"password_changed"}',
    );
    socket.start();
    expect(socket.connection.value, isNot(SocketState.expired));
  });
}
