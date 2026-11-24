import 'dart:async';

import 'package:connectum/data/socket/socket_service.dart';

import '../support/fake_socket.dart';

/// A clock whose `delay` moves time instead of waiting.
class GateClock {
  DateTime now = DateTime(2026, 11, 24, 12);
  final waits = <Duration>[];

  DateTime read() => now;

  Future<void> delay(Duration d) async {
    waits.add(d);
    now = now.add(d);
    await Future<void>.delayed(Duration.zero);
  }
}

typedef HeldCall = ({
  String action,
  Map<String, dynamic> args,
  Completer<Map<String, dynamic>> done,
});

/// A socket whose answers the test completes by hand (or [handler] gives).
class HeldSocket extends FakeSocket {
  final waiting = <HeldCall>[];
  Future<Map<String, dynamic>> Function(
    String action,
    Map<String, dynamic> args,
  )?
  handler;

  @override
  Future<Map<String, dynamic>> sdCall(
    String action,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 12),
  }) {
    if (!isOnline) throw const SocketCallError('not_connected');
    calls.add((action: action, args: args));
    final h = handler;
    if (h != null) return h(action, args);
    final done = Completer<Map<String, dynamic>>();
    waiting.add((action: action, args: args, done: done));
    return done.future;
  }
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
