import 'dart:async';

import 'package:connectum/data/socket/read_gate.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_support.dart';

void main() {
  late GateClock clock;
  late ReadGate gate;

  setUp(() {
    clock = GateClock();
    gate = ReadGate(now: clock.read, delay: clock.delay);
  });

  test('the budget is 20 reads per 10 s, under the server\'s 30', () {
    expect(ReadGate.budget, 20);
    expect(ReadGate.window, const Duration(seconds: 10));
  });

  test('never more than the budget in any 10 seconds, 300 ms apart', () async {
    final times = <DateTime>[];
    for (var i = 0; i < 120; i++) {
      await gate.run(() async => times.add(clock.now));
    }
    expect(times.length, 120);
    for (final t in times) {
      final inWindow = times.where(
        (x) => !x.isBefore(t) && x.difference(t) < ReadGate.window,
      );
      expect(inWindow.length, lessThanOrEqualTo(ReadGate.budget));
    }
    for (var i = 1; i < times.length; i++) {
      expect(
        times[i].difference(times[i - 1]),
        greaterThanOrEqualTo(ReadGate.gap),
      );
    }
  });

  test('reads asked together go one at a time, in order', () async {
    var running = 0;
    var most = 0;
    final order = <int>[];
    await Future.wait([
      for (var i = 0; i < 6; i++)
        gate.run(() async {
          running++;
          most = running > most ? running : most;
          await Future<void>.delayed(Duration.zero);
          order.add(i);
          running--;
        }),
    ]);
    expect(most, 1);
    expect(order, [0, 1, 2, 3, 4, 5]);
  });

  test(
    'rate_limited: a growing pause 1, 2, 3 s, then the read goes out',
    () async {
      var n = 0;
      final result = await gate.run(() async {
        if (++n <= 3) throw const SocketCallError('rate_limited', 'slow');
        return 'ok';
      });
      expect(result, 'ok');
      expect(n, 4);
      final pauses = clock.waits.where((w) => w >= const Duration(seconds: 1));
      expect(pauses.map((w) => w.inSeconds), [1, 2, 3]);
      expect(gate.sent, 4);
    },
  );

  test(
    'busy is retried too; after four refusals the error goes to the caller',
    () async {
      var n = 0;
      await expectLater(
        gate.run(() async {
          n++;
          throw const SocketCallError('busy');
        }),
        throwsA(isA<SocketCallError>().having((e) => e.code, 'code', 'busy')),
      );
      expect(n, ReadGate.maxRetries + 1);
    },
  );

  test('any other error is not retried', () async {
    var n = 0;
    await expectLater(
      gate.run(() async {
        n++;
        throw const SocketCallError('forbidden');
      }),
      throwsA(isA<SocketCallError>()),
    );
    expect(n, 1);
    expect(clock.waits, isEmpty);
  });

  test('a refused read does not stop the next one', () async {
    final failed = gate.run<void>(() async => throw const SocketCallError('x'));
    final after = gate.run(() async => 7);
    await expectLater(failed, throwsA(isA<SocketCallError>()));
    expect(await after, 7);
  });

  test(
    'a rate_limited answer pauses every reader, not only that read',
    () async {
      var n = 0;
      final first = gate.run(() async {
        if (++n == 1) throw const SocketCallError('rate_limited');
        return 'a';
      });
      final started = <DateTime>[];
      final second = gate.run(() async {
        started.add(clock.now);
        return 'b';
      });
      final t0 = clock.now;
      expect(await first, 'a');
      expect(await second, 'b');
      expect(
        started.single.difference(t0),
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
    },
  );

  test('a queue with its own timer counts against the same budget', () {
    for (var i = 0; i < ReadGate.budget; i++) {
      gate.markStart();
    }
    expect(gate.waitFor(), const Duration(seconds: 10));
    clock.now = clock.now.add(const Duration(seconds: 10));
    expect(gate.waitFor(), Duration.zero);
  });

  test('blockFor holds reads back', () async {
    gate.blockFor(const Duration(seconds: 4));
    expect(gate.waitFor(), const Duration(seconds: 4));
    final t0 = clock.now;
    DateTime? at;
    await gate.run(() async => at = clock.now);
    expect(at!.difference(t0), const Duration(seconds: 4));
  });

  test('nothing is sent while an earlier read is still waiting', () async {
    final hold = Completer<void>();
    final order = <String>[];
    final a = gate.run(() async {
      order.add('a start');
      await hold.future;
      order.add('a end');
    });
    final b = gate.run(() async => order.add('b'));
    await settle();
    expect(order, ['a start']);
    hold.complete();
    await Future.wait([a, b]);
    expect(order, ['a start', 'a end', 'b']);
  });
}
