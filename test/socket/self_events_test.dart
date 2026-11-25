import 'dart:async';

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
  late List<String> seen;
  late StreamSubscription<Map<String, dynamic>> sub;

  setUp(() {
    socket = SocketService(_Session(), _Connectivity(), _Api())..start();
    seen = [];
    sub = socket.unfilteredEventsForTest.listen(
      (e) => seen.add('${e['type']}'),
    );
  });

  tearDown(() => sub.cancel());

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  const names = ['self_message', 'self_edited', 'self_deleted', 'self_ack'];
  final padding = 'x' * (SocketService.decodeThreshold + 10);

  for (final name in names) {
    test('$name is delivered in both shapes, in order', () async {
      socket.receiveForTest(
        '{"type":"$name","text":"hi","replyTo":"7","cid":"m-1","extra":{"a":1}}',
      );
      socket.receiveForTest(
        '{"type":"sd_event","event":"$name","data":{"text":"hi","replyTo":"7"}}',
      );
      socket.receiveForTest('{"type":"private","from":"bob","text":"next"}');
      await settle();
      expect(seen, [name, 'sd_event', 'private']);
    });

    test('$name above the decode threshold keeps the order', () async {
      socket.receiveForTest('{"type":"m"}');
      socket.receiveForTest(
        '{"type":"$name","text":"hi","replyTo":"7","pad":"$padding"}',
      );
      socket.receiveForTest('{"type":"private","from":"bob"}');
      await settle();
      expect(seen, ['m', name, 'private']);
    });
  }
}
