import 'dart:async';

import 'package:connectum/core/routes/home_reload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => HomeReload.body = () async {});

  test('triggers during a run become one follow-up run', () async {
    var runs = 0;
    var overlap = 0;
    var maxOverlap = 0;
    final gate = Completer<void>();
    HomeReload.body = () async {
      runs++;
      overlap++;
      if (overlap > maxOverlap) maxOverlap = overlap;
      if (runs == 1) await gate.future;
      overlap--;
    };
    final first = HomeReload.run();
    final second = HomeReload.run();
    final third = HomeReload.run();
    gate.complete();
    await Future.wait([first, second, third]);
    expect(runs, 2);
    expect(maxOverlap, 1);
    expect(HomeReload.isRunning, isFalse);
  });

  test('a failed run does not block the next one', () async {
    HomeReload.body = () async => throw StateError('boom');
    await expectLater(HomeReload.run(), throwsStateError);
    var ran = false;
    HomeReload.body = () async => ran = true;
    await HomeReload.run();
    expect(ran, isTrue);
  });
}
