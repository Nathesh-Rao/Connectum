import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

import 'package:connectum/features/ai_agents/ai_agents_view.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: const AiAgentsView(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('shows the robot, title and subtitle', (tester) async {
    await _pump(tester, size: const Size(360, 640));
    expect(find.byType(Lottie), findsOneWidget);
    expect(find.text(AiAgentsView.title), findsOneWidget);
    expect(find.text(AiAgentsView.subtitle), findsOneWidget);
    final lottie = tester.widget<Lottie>(find.byType(Lottie));
    expect(lottie.repeat, isTrue);
    expect(lottie.animate, isTrue);
    expect(tester.getSize(find.byType(Lottie)).width, 360 - 48);
  });

  testWidgets('is capped at 420 on a wide screen', (tester) async {
    await _pump(tester, size: const Size(900, 1000));
    final box = tester.getSize(find.byType(Lottie));
    expect(box.width, box.height);
    expect(box.height, 420);
  });

  testWidgets('does not overflow at 360x640', (tester) async {
    await _pump(tester, size: const Size(360, 640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not overflow at text scale 2.0', (tester) async {
    await _pump(tester, size: const Size(360, 640), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text(AiAgentsView.title), findsOneWidget);
  });

  testWidgets('does not overflow in landscape', (tester) async {
    await _pump(tester, size: const Size(640, 360));
    expect(tester.takeException(), isNull);
    expect(find.byType(Lottie), findsOneWidget);
  });

  testWidgets('reduced motion stops the animation', (tester) async {
    await _pump(tester, size: const Size(360, 640), disableAnimations: true);
    final lottie = tester.widget<Lottie>(find.byType(Lottie));
    expect(lottie.animate, isFalse);
    expect(lottie.controller, isA<AlwaysStoppedAnimation<double>>());
  });
}
