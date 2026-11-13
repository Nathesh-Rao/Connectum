import 'dart:ui' as ui;

import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/widgets/logo_intro/logo_intro.dart';
import 'package:connectum/core/widgets/logo_intro/logo_intro_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(300, 300);

Widget _host(Widget child, {bool isReduced = false}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: MediaQueryData(disableAnimations: isReduced),
    child: Center(child: child),
  ),
);

CustomPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.descendant(
        of: find.byType(LogoIntro),
        matching: find.byType(CustomPaint),
      ),
    )
    .painter!;

TestRecordingCanvas _record(WidgetTester tester) {
  final canvas = TestRecordingCanvas();
  _painter(tester).paint(canvas, _size);
  return canvas;
}

String _arg(Object? a) {
  if (a is ui.Path) return 'path${a.getBounds()}';
  if (a is Paint) {
    return 'paint(${a.color},${a.maskFilter != null},${a.shader != null})';
  }
  if (a is Iterable) return a.map(_arg).toString();
  return '$a';
}

/// Every canvas call with its arguments: equal signatures mean equal frames.
List<String> _signature(TestRecordingCanvas c) => [
  for (final i in c.invocations)
    '${i.invocation.memberName}:${i.invocation.positionalArguments.map(_arg)}',
];

Iterable<RecordedInvocation> _calls(TestRecordingCanvas c, Symbol name) =>
    c.invocations.where((i) => i.invocation.memberName == name);

double _length(ui.Path p) =>
    p.computeMetrics().fold(0.0, (sum, m) => sum + m.length);

Future<List<String>> _frameAt(WidgetTester tester, double t) async {
  await tester.pumpWidget(
    _host(LogoIntro(size: 300, timeOverride: ValueNotifier(t))),
  );
  return _signature(_record(tester));
}

void main() {
  testWidgets('final frame draws the exact original artwork', (tester) async {
    final time = ValueNotifier<double>(LogoIntro.duration);
    await tester.pumpWidget(_host(LogoIntro(size: 300, timeOverride: time)));
    final paths = _calls(_record(tester), #drawPath).toList();
    final originals = buildIntroOriginalPaths();
    final letters = buildIntroLetterPaths();
    expect(paths.length, originals.length + letters.length);
    for (var i = 0; i < originals.length; i++) {
      final args = paths[i].invocation.positionalArguments;
      final drawn = args[0] as ui.Path;
      expect(drawn.getBounds(), originals[i].getBounds(), reason: 'piece $i');
      expect(_length(drawn), closeTo(_length(originals[i]), 1e-6));
      expect((args[1] as Paint).color.toARGB32(), introPieces[i].color);
      expect((args[1] as Paint).maskFilter, isNull);
    }
    for (var i = 0; i < letters.length; i++) {
      final args = paths[originals.length + i].invocation.positionalArguments;
      expect((args[0] as ui.Path).getBounds(), letters[i].getBounds());
      expect((args[1] as Paint).maskFilter, isNull);
    }
  });

  testWidgets('the union of the drawn pieces is the data bounds', (
    tester,
  ) async {
    final time = ValueNotifier<double>(LogoIntro.duration);
    await tester.pumpWidget(_host(LogoIntro(size: 300, timeOverride: time)));
    final drawn = _calls(_record(tester), #drawPath)
        .take(IntroGeo.count)
        .map((i) => (i.invocation.positionalArguments[0] as ui.Path))
        .map((p) => p.getBounds())
        .reduce((a, b) => a.expandToInclude(b));
    final data = buildIntroOriginalPaths()
        .map((p) => p.getBounds())
        .reduce((a, b) => a.expandToInclude(b));
    expect(drawn, data);
  });

  testWidgets('defaults use the app tokens', (tester) async {
    const intro = LogoIntro();
    expect(intro.ink, AppColors.ink);
    expect(intro.ball, AppColors.primaryBright);
    expect(intro.glowInner, AppColors.primaryBright);
    expect(intro.glowOuter, AppColors.primaryLight);
    expect(intro.shine, AppColors.white);
    expect(intro.speed, 1.0);
    expect(intro.finishAt, IntroTiming.duration);
    expect(intro.blurLetters, isTrue);
    expect(intro.glowFinal, 0.55);
  });

  testWidgets('timeOverride drives the painter and no ticker runs', (
    tester,
  ) async {
    final time = ValueNotifier<double>(1.0);
    await tester.pumpWidget(_host(LogoIntro(size: 300, timeOverride: time)));
    expect(tester.binding.transientCallbackCount, 0);
    final a = _signature(_record(tester));
    await tester.pump(const Duration(seconds: 1));
    expect(_signature(_record(tester)), a);
    time.value = 2.0;
    await tester.pump();
    final b = _signature(_record(tester));
    expect(b, isNot(a));
    expect(b, await _frameAt(tester, 2.0));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('speed scales elapsed time', (tester) async {
    await tester.pumpWidget(_host(const LogoIntro(size: 300, speed: 2)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final fast = _signature(_record(tester));
    expect(fast, await _frameAt(tester, 2.0));

    await tester.pumpWidget(_host(const LogoIntro(size: 300, speed: 0.5)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final slow = _signature(_record(tester));
    expect(slow, await _frameAt(tester, 1.0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('finishAt fires once, earlier than the end, animation goes on', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(
      _host(LogoIntro(size: 300, finishAt: 1.0, onFinished: () => count++)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(count, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(count, 1);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pump(const Duration(seconds: 6));
    expect(count, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(_signature(_record(tester)), await _frameAt(tester, 99));
  });

  testWidgets('finishAt is on the authored timeline, divided by speed', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(
      _host(
        LogoIntro(
          size: 300,
          speed: 2,
          finishAt: 2.0,
          onFinished: () => count++,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(count, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(count, 1);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('default finishAt fires at the end', (tester) async {
    var count = 0;
    await tester.pumpWidget(
      _host(LogoIntro(size: 300, onFinished: () => count++)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(count, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(count, 1);
  });

  testWidgets('replay resets the finished flag', (tester) async {
    var count = 0;
    final controller = LogoIntroController();
    await tester.pumpWidget(
      _host(
        LogoIntro(
          size: 300,
          controller: controller,
          finishAt: 1.0,
          onFinished: () => count++,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    expect(count, 1);
    controller.replay();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(count, 1);
    await tester.pump(const Duration(seconds: 7));
    expect(count, 2);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('reduced motion shows the final frame and finishes promptly', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(
      _host(LogoIntro(size: 300, onFinished: () => count++), isReduced: true),
    );
    await tester.pump();
    expect(count, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(_signature(_record(tester)), await _frameAt(tester, 99));
  });

  testWidgets('reduced motion switched on mid-animation jumps to the end', (
    tester,
  ) async {
    var count = 0;
    Widget build(bool isReduced) => _host(
      LogoIntro(size: 300, onFinished: () => count++),
      isReduced: isReduced,
    );
    await tester.pumpWidget(build(false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(count, 0);
    await tester.pumpWidget(build(true));
    await tester.pump();
    expect(count, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(_signature(_record(tester)), await _frameAt(tester, 99));
  });

  testWidgets('blurLetters false removes the letter blur', (tester) async {
    bool hasBlur(TestRecordingCanvas c) => _calls(c, #drawPath).any(
      (i) => (i.invocation.positionalArguments[1] as Paint).maskFilter != null,
    );
    final time = ValueNotifier<double>(3.0);
    await tester.pumpWidget(_host(LogoIntro(size: 300, timeOverride: time)));
    expect(hasBlur(_record(tester)), isTrue);
    await tester.pumpWidget(
      _host(LogoIntro(size: 300, timeOverride: time, blurLetters: false)),
    );
    expect(hasBlur(_record(tester)), isFalse);
  });

  testWidgets('glowFinal 0 removes the bloom of the final still', (
    tester,
  ) async {
    final time = ValueNotifier<double>(LogoIntro.duration);
    await tester.pumpWidget(_host(LogoIntro(size: 300, timeOverride: time)));
    expect(_calls(_record(tester), #drawCircle), hasLength(1));
    await tester.pumpWidget(
      _host(LogoIntro(size: 300, timeOverride: time, glowFinal: 0)),
    );
    expect(_calls(_record(tester), #drawCircle), isEmpty);
  });
}
