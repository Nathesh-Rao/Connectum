import 'package:connectum/core/tour/tour_gesture.dart';
import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_step.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:connectum/core/tour/widgets/tour_card.dart';
import 'package:connectum/features/commands/commands_tour.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/features/conversation/conversation_tour.dart';
import 'package:connectum/features/workspace/workspace_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tour_test_support.dart';

void main() {
  setUpAll(loadAppFont);
  final service = TourService(userId: () => 'u1', store: memoryStore());

  List<TourStep> allSteps() {
    final chat = ConversationTour(service: service);
    final ws = WorkspaceTour(service: service);
    final cmd = CommandsTour(service: service, isListOpen: () => true);
    return [
      for (final e in [true, false])
        for (final b in [true, false])
          ...chat.steps(
            ConversationTourCaps(
              isEncrypted: e,
              isBlocked: b,
              canAttach: true,
              canReact: true,
              canEdit: true,
              canReply: true,
            ),
            hasMessage: false,
          ),
      ...ws.steps(hasNote: false),
      ...cmd.steps(),
    ];
  }

  testWidgets('every new step fits at 320 px and 1.5x text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final step in allSteps()) {
      for (final isLast in [false, true]) {
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
                    step: step,
                    index: isLast ? 4 : 0,
                    total: 5,
                    isReduced: false,
                    onNext: () {},
                    onSkip: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.takeException(), isNull, reason: step.title);
        final rect = tester.getRect(find.byType(TourCard));
        expect(rect.left, greaterThanOrEqualTo(0), reason: step.title);
        expect(rect.right, lessThanOrEqualTo(320), reason: step.title);
        expect(rect.top, greaterThanOrEqualTo(0), reason: step.title);
        expect(rect.bottom, lessThanOrEqualTo(640), reason: step.title);
      }
    }
  });

  testWidgets('a target that fills the screen gets its card inside it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final area = GlobalKey();
    final small = GlobalKey();
    final bar = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(key: small, height: 60, width: double.infinity),
              Expanded(
                child: SizedBox(key: area, width: double.infinity),
              ),
              SizedBox(key: bar, height: 70, width: double.infinity),
            ],
          ),
        ),
      ),
    );
    final tour = TourService(userId: () => 'u1', store: memoryStore())
      ..bottomBarKey = bar;
    final context = tester.element(find.byKey(small));
    await tour.start(TourId.chatList, [
      TourStep(
        target: area,
        icon: Icons.touch_app,
        title: 'Press and hold',
        body: TourTexts.chatHoldBody(canReact: true),
        gesture: TourGesture.longPress,
      ),
      TourStep(target: small, icon: Icons.info, title: 'B', body: 'b'),
    ], context: context);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final card = tester.getRect(find.byType(TourCard));
    final target = tester.getRect(find.byKey(area));
    expect(card.top, greaterThanOrEqualTo(target.top));
    expect(card.bottom, lessThanOrEqualTo(target.bottom));
    tour.cancel();
    await tester.pump();
  });
}
