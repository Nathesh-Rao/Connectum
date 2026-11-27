import 'package:connectum/core/tour/tour_gesture.dart';
import 'package:connectum/core/tour/tour_step.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:connectum/core/tour/widgets/tour_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required int index,
    int total = 5,
    TourGesture? gesture,
    bool isReduced = false,
  }) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TourCard(
                step: TourStep(
                  target: GlobalKey(),
                  icon: Icons.search,
                  title: 'Find anything',
                  body: TourTexts.chatSearchBody,
                  gesture: gesture,
                ),
                index: index,
                total: total,
                isReduced: isReduced,
                onNext: () {},
                onSkip: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('fits at 320 px and 1.5x text, first step', (tester) async {
    await pumpCard(tester, index: 0, gesture: TourGesture.longPress);
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byType(TourCard));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(640));
    expect(find.text(TourTexts.skip), findsOneWidget);
    expect(find.text(TourTexts.next), findsOneWidget);
  });

  testWidgets('the last step says Got it and every hint fits', (tester) async {
    for (final g in TourGesture.values) {
      await pumpCard(tester, index: 4, gesture: g);
      expect(tester.takeException(), isNull, reason: g.name);
      expect(find.text(TourTexts.done), findsOneWidget);
      expect(
        tester.getRect(find.byType(TourCard)).right,
        lessThanOrEqualTo(320),
      );
    }
  });

  testWidgets('Next and Skip have semantics labels', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCard(tester, index: 1);
    expect(find.bySemanticsLabel(TourTexts.nextLabel), findsOneWidget);
    expect(find.bySemanticsLabel(TourTexts.skipLabel), findsOneWidget);
    handle.dispose();
  });

  testWidgets('with reduce motion the hint is a still frame', (tester) async {
    await pumpCard(
      tester,
      index: 0,
      gesture: TourGesture.swipeLeft,
      isReduced: true,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
