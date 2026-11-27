import 'package:connectum/core/tour/tour_gesture.dart';
import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_step.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:connectum/core/tour/widgets/tour_card.dart';
import 'package:connectum/features/inbox/inbox_tour.dart';
import 'package:connectum/features/notifications/notifications_tour.dart';
import 'package:connectum/features/profile/profile_tour.dart';
import 'package:connectum/features/smart_view/smart_view_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tour_test_support.dart';

void main() {
  setUpAll(loadAppFont);
  late TourService service;

  setUp(() {
    service = TourService(userId: () => 'u1', store: memoryStore());
  });

  group('notifications', () {
    late NotificationsTour tour;
    setUp(() => tour = NotificationsTour(service: service));

    test('four steps; with a tile the gestures point at it', () {
      final s = tour.steps(hasTile: true);
      expect(s.length, 4);
      expect(s[1].target, tour.tileKey);
      expect(s[2].target, tour.tileKey);
      expect(s[2].gesture, TourGesture.swipeLeft);
    });

    test('with none the gestures point at the body and show a hint', () {
      final s = tour.steps(hasTile: false);
      expect(s[1].target, tour.bodyKey);
      expect(s[2].target, tour.bodyKey);
      expect(s[1].gesture, TourGesture.tap);
      expect(s[1].body, TourTexts.ntTapEmptyBody);
    });
  });

  group('profile', () {
    test('five steps, the last one is the replay row', () {
      final tour = ProfileTour(service: service);
      final s = tour.steps();
      expect(s.length, 5);
      expect(s[1].target, tour.statusKey);
      expect(s.last.target, tour.replayKey);
      expect(s.last.body, contains('Replay all tours'));
      expect(s.first.canScroll, isFalse);
      expect(s.skip(1).every((x) => x.canScroll), isTrue);
    });
  });

  group('on screen', () {
    testWidgets('every new tour waits for chatList and is not marked', (
      tester,
    ) async {
      final sv = SmartViewTour(service: service);
      final inbox = InboxTour(service: service);
      final nt = NotificationsTour(service: service);
      final pr = ProfileTour(service: service);
      useTallScreen(tester);
      await tester.pumpWidget(
        TourHarness(keys: [sv.menuKey, sv.drawerKey, inbox.tabsKey], shown: 3),
      );
      expect(
        await service.start(
          TourId.smartView,
          sv.steps(_svPorts(), isSample: true),
          context: tester.element(find.byKey(sv.menuKey)),
          after: TourId.chatList,
        ),
        TourStart.notReady,
      );
      expect(await service.isSeen(TourId.smartView), isFalse);
      // The real entry points use the same rule.
      expect(await sv.start(_svPorts(), isSample: true), TourStart.notReady);
      expect(await nt.start(), TourStart.failed);
      expect(await pr.start(), TourStart.blocked);
      expect(
        await inbox.start(_inboxPorts(), isSample: true),
        TourStart.notReady,
      );
    });

    testWidgets('an account with no notifications gets all four steps', (
      tester,
    ) async {
      final tour = NotificationsTour(service: service);
      useTallScreen(tester);
      await tester.pumpWidget(
        TourHarness(
          keys: [tour.pillsKey, tour.bodyKey, tour.moreKey],
          shown: 3,
        ),
      );
      await service.markSeen(TourId.chatList);
      expect(await tour.start(), TourStart.started);
      await pumpTour(tester);
      for (final title in [
        TourTexts.ntPillsTitle,
        TourTexts.ntTapTitle,
        TourTexts.ntSwipeTitle,
      ]) {
        expect(find.text(title), findsOneWidget);
        await tester.tap(find.text(TourTexts.next));
        await pumpTour(tester);
      }
      expect(find.text(TourTexts.ntMoreTitle), findsOneWidget);
      await tester.tap(find.text(TourTexts.done));
      await tester.pump();
      expect(await service.isSeen(TourId.notifications), isTrue);
    });

    testWidgets('the profile tour scrolls to a row below the fold', (
      tester,
    ) async {
      final tour = ProfileTour(service: service);
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  SizedBox(
                    key: tour.identityKey,
                    width: double.infinity,
                    height: 120,
                  ),
                  SizedBox(
                    key: tour.statusKey,
                    width: double.infinity,
                    height: 60,
                  ),
                  const SizedBox(height: 1000),
                  SizedBox(
                    key: tour.securityKey,
                    width: double.infinity,
                    height: 60,
                  ),
                  const SizedBox(height: 1000),
                  SizedBox(
                    key: tour.switchKey,
                    width: double.infinity,
                    height: 60,
                  ),
                  const SizedBox(height: 1000),
                  SizedBox(
                    key: tour.replayKey,
                    width: double.infinity,
                    height: 60,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      );
      await service.markSeen(TourId.chatList);
      expect(await tour.start(), TourStart.started);
      await pumpTour(tester);
      expect(scroll.offset, 0);
      await tester.tap(find.text(TourTexts.next));
      await pumpTour(tester);
      expect(find.text(TourTexts.prStatusTitle), findsOneWidget);
      await tester.tap(find.text(TourTexts.next));
      await pumpTour(tester);
      expect(find.text(TourTexts.prSecurityTitle), findsOneWidget);
      expect(TourService.isVisible(tour.securityKey), isTrue);
      expect(scroll.offset, greaterThan(0));
      await tester.tap(find.text(TourTexts.next));
      await pumpTour(tester);
      await tester.tap(find.text(TourTexts.next));
      await pumpTour(tester);
      expect(find.text(TourTexts.prReplayTitle), findsOneWidget);
      expect(TourService.isVisible(tour.replayKey), isTrue);
      service.cancel();
      await tester.pump();
    });
  });

  testWidgets('every new step fits at 320 px and 1.5x text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sv = SmartViewTour(service: service);
    final inbox = InboxTour(service: service);
    final nt = NotificationsTour(service: service);
    final pr = ProfileTour(service: service);
    final all = <TourStep>[
      for (final s in [true, false])
        for (final f in [true, false])
          ...sv.steps(_svPorts(), isSample: s, hasFiles: f),
      for (final s in [true, false])
        for (final p in [0, 7])
          ...inbox.steps(_inboxPorts(), isSample: s, pendingApprovals: p),
      ...nt.steps(hasTile: true),
      ...nt.steps(hasTile: false),
      ...pr.steps(),
    ];
    for (final step in all) {
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
                    index: isLast ? 3 : 0,
                    total: 4,
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
}

SvTourPorts _svPorts() => SvTourPorts(
  seed: () => false,
  restore: () {},
  openDrawer: () {},
  closeDrawer: () {},
  pick: () {},
  unpick: () {},
  expandFirst: () {},
  collapseFirst: () {},
  openFilter: () {},
  closeFilter: () {},
);

InboxTourPorts _inboxPorts() => InboxTourPorts(
  seed: () => false,
  restore: () {},
  expandFirst: () {},
  collapseFirst: () {},
  openFilter: () {},
  closeFilter: () {},
  showApprovals: () {},
  showRecords: () {},
);
