import 'dart:async';

import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends Fake implements SessionStore {}

class _Connectivity extends Fake implements ConnectivityService {}

class _Api extends Fake implements ApiClient {}

void main() {
  late SocketService socket;

  setUp(() {
    socket = SocketService(_Session(), _Connectivity(), _Api());
  });

  test('backoff doubles from 1 s and is capped at 15 s', () {
    expect(
      [for (var i = 0; i < 7; i++) SocketService.backoff(i).inSeconds],
      [1, 2, 4, 8, 15, 15, 15],
    );
  });

  test(
    'a call while not connected fails with not_connected, no stray error',
    () {
      expect(
        socket.sdCall('x', {}),
        throwsA(
          isA<SocketCallError>().having((e) => e.code, 'code', 'not_connected'),
        ),
      );
    },
  );

  test(
    'a drop mid-run ends it quietly and the next welcome runs it again',
    () async {
      var runs = 0;
      socket.listenOnline('t', () async {
        runs++;
        if (runs == 1) throw const SocketCallError('disconnected');
        if (runs == 2) throw StateError('dropped');
      });
      socket.emitOnline();
      await Future<void>.delayed(Duration.zero);
      socket.emitOnline();
      await Future<void>.delayed(Duration.zero);
      socket.emitOnline();
      await Future<void>.delayed(Duration.zero);
      expect(runs, 3);
    },
  );

  test('triggers during a run coalesce into one follow-up', () async {
    var runs = 0;
    final gate = Completer<void>();
    socket.listenOnline('t', () async {
      runs++;
      if (runs == 1) await gate.future;
    });
    socket.emitOnline();
    socket.emitOnline();
    socket.emitOnline();
    await Future<void>.delayed(Duration.zero);
    expect(runs, 1);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(runs, 2);
  });
}
