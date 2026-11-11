import 'package:connectum/core/widgets/logo_loader/logo_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stopAndWait on a controller that never mounted returns at once',
    () async {
      final c = LogoLoaderController();
      expect(c.start(), isTrue);
      await expectLater(
        c.stopAndWait().timeout(const Duration(seconds: 1)),
        completes,
      );
      expect(c.isIdle, isTrue);
      c.dispose();
    },
  );

  test(
    'stopAndWait and whenIdle on an idle controller return at once',
    () async {
      final c = LogoLoaderController();
      await expectLater(
        c.stopAndWait().timeout(const Duration(seconds: 1)),
        completes,
      );
      await expectLater(
        c.whenIdle.timeout(const Duration(seconds: 1)),
        completes,
      );
      c.dispose();
    },
  );

  testWidgets('dispose of the controller completes pending waiters', (
    tester,
  ) async {
    final c = LogoLoaderController();
    await tester.pumpWidget(MaterialApp(home: LogoLoader(controller: c)));
    c.start();
    await tester.pump(const Duration(milliseconds: 100));
    var isDone = false;
    c.stopAndWait().then((_) => isDone = true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(isDone, isFalse);
    c.dispose();
    await tester.pump();
    expect(isDone, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unmounting the widget mid-stop completes pending waiters', (
    tester,
  ) async {
    final c = LogoLoaderController();
    await tester.pumpWidget(MaterialApp(home: LogoLoader(controller: c)));
    c.start();
    await tester.pump(const Duration(milliseconds: 100));
    var isDone = false;
    c.stopAndWait().then((_) => isDone = true);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(isDone, isTrue);
    expect(c.isIdle, isTrue);
    c.dispose();
  });

  testWidgets('a mounted controller still plays the full stop transition', (
    tester,
  ) async {
    final c = LogoLoaderController();
    await tester.pumpWidget(MaterialApp(home: LogoLoader(controller: c)));
    c.start();
    await tester.pump(const Duration(milliseconds: 100));
    var isDone = false;
    c.stopAndWait().then((_) => isDone = true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(isDone, isFalse);
    for (var i = 0; i < 60 && !isDone; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(isDone, isTrue);
    expect(c.p, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
