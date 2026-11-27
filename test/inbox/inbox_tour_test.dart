import 'dart:async';

import 'package:connectum/core/tour/tour_gesture.dart';
import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:connectum/features/home_shell/home_tab.dart';
import 'package:connectum/features/inbox/inbox_tour.dart';
import 'package:connectum/features/inbox/inbox_tour_demo.dart';
import 'package:connectum/features/inbox/inbox_view.dart';
import 'package:connectum/features/inbox/models/inbox_tab.dart';
import 'package:connectum/features/inbox/widgets/approval_card.dart';
import 'package:connectum/features/inbox/widgets/inbox_card.dart';
import 'package:connectum/features/inbox/widgets/inbox_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../core/tour/tour_test_support.dart';
import 'inbox_screen_support.dart';

Map<String, dynamic> _request(int id) => {
  'id': id,
  'type': 'submission',
  'status': 'pending',
  'from': 'rhea',
  'fromName': 'Rhea Rao',
  'approvers': ['ana'],
  'direction': 'incoming',
  'canRespond': true,
  'createdTs': DateTime(2026, 11, 20, 9, id).millisecondsSinceEpoch,
  'data': {
    'caption': 'Real expense claim',
    'tstruct': 'expense',
    'stage': 1,
    'stages': 2,
    'summary': [
      {'caption': 'Amount', 'value': '120'},
    ],
  },
};

enum _Exit { finish, skip, cancel, leaveTab }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFont);

  late TourService service;
  late InboxRig rig;
  late InboxTour tour;

  Future<void> boot(
    WidgetTester tester, {
    bool hasRecords = false,
    bool hasRequests = false,
    double width = 390,
    double scale = 1,
  }) async {
    service = TourService(userId: () => 'u1', store: memoryStore());
    await service.markSeen(TourId.chatList);
    tour = InboxTour(service: service);
    rig = InboxRig(tour: tour);
    addTearDown(rig.dispose);
    rig.routes['records.query'] = (_) =>
        queryReply([if (hasRecords) record(2), if (hasRecords) record(1)]);
    rig.routes['req.list'] = (_) => {
      'requests': [if (hasRequests) _request(7)],
      'total': hasRequests ? 1 : 0,
      'hasMore': false,
    };
    Get.put(rig.controller);
    addTearDown(Get.reset);
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: const InboxView(),
      ),
    );
    for (var i = 0; i < 40 && !service.isActive.value; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pumpTour(tester);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text(TourTexts.next));
    await pumpTour(tester);
    await pumpTour(tester);
    expect(tester.takeException(), isNull);
  }

  void expectClean(InboxRig rig) {
    final c = rig.controller;
    final d = tour.demo;
    expect(service.isActive.value, isFalse);
    expect(c.tabIndex.value, 0, reason: 'back on Records');
    expect(d.isRecordsSample.value, isFalse);
    expect(d.isApprovalsSample.value, isFalse);
    expect(d.isFilterOpen.value, isFalse);
    expect(d.expanded, isEmpty);
    expect(d.rows, isEmpty);
    expect(d.approvals, isEmpty);
    expect(d.isDriving, isFalse);
  }

  group('the steps', () {
    test('seven at most, in order, with the tab switch a swipe', () {
      final t = InboxTour(
        service: TourService(userId: () => 'u1', store: memoryStore()),
      );
      final p = _ports();
      final steps = t.steps(p, isSample: true);
      expect(steps.length, lessThanOrEqualTo(7));
      expect(steps.map((s) => s.title), [
        TourTexts.inboxCardsTitle,
        TourTexts.inboxExpandTitle,
        TourTexts.inboxViewsTitle,
        TourTexts.inboxSearchTitle,
        TourTexts.inboxTabsTitle,
        TourTexts.inboxFilterBarTitle,
        TourTexts.inboxApprovalsTitle,
      ]);
      final tabs = steps[4].actions.single;
      expect(tabs.gesture, TourGesture.swipeLeft);
      expect(tabs.target, t.pagesKey);
      // The later steps keep the Approvals tab on without a second swipe.
      expect(steps[5].actions.single.carry, tabs.carry);
      expect(steps[6].actions.single.carry, tabs.carry);
      expect(steps[5].actions.single.gesture, isNull);
      expect(TourId.inbox.version, 2);
    });
  });

  group('an account with no records and no requests', () {
    testWidgets('runs the whole tour on samples and puts everything back', (
      tester,
    ) async {
      await boot(tester);
      expect(service.isActive.value, isTrue);
      final c = rig.controller;
      final asked = rig.asked.length;
      final d = tour.demo;

      // 1. The cards: two real InboxCards marked Sample.
      expect(find.text(TourTexts.inboxCardsTitle), findsOneWidget);
      expect(find.byType(InboxCard), findsNWidgets(2));
      expect(find.text(TourTexts.sampleTag), findsNWidgets(2));
      expect(find.byKey(const ValueKey('inbox-avatar-ring')), findsWidgets);
      // The sample never reaches a count, a badge or a list.
      expect(c.rows, isEmpty);
      expect(c.badgeOf(InboxTab.approvals), 0);
      expect(c.pillOf(InboxTab.records), '0', reason: 'the real total');
      expect(c.approvals.hasListed, isFalse);

      // 2. A card opens.
      await next(tester);
      expect(find.text(TourTexts.inboxExpandTitle), findsOneWidget);
      expect(d.expanded, {'r-101'});

      // 3. Views: the card is closed again.
      await next(tester);
      expect(find.text(TourTexts.inboxViewsTitle), findsOneWidget);
      expect(d.expanded, isEmpty);

      // 4. Search and the filter popup, on a panel that reads nothing.
      await next(tester);
      expect(find.text(TourTexts.inboxSearchTitle), findsOneWidget);
      expect(d.isFilterOpen.value, isTrue);
      expect(find.byType(InboxFilterPanel), findsOneWidget);

      // 5. The tab really switches; the popup is gone.
      await next(tester);
      expect(find.text(TourTexts.inboxTabsTitle), findsOneWidget);
      expect(d.isFilterOpen.value, isFalse);
      expect(find.byType(InboxFilterPanel), findsNothing);
      expect(c.tabIndex.value, 1);
      expect(c.isApprovalsOpen, isTrue);

      // 6. The Approvals filter button and its chips.
      await next(tester);
      expect(find.text(TourTexts.inboxFilterBarTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('approvals-filter')), findsOne);
      expect(find.byKey(const ValueKey('approval-selected-all')), findsNothing);
      expect(c.tabIndex.value, 1);

      // 7. A connection request and a form with its three answers.
      await next(tester);
      expect(find.text(TourTexts.inboxApprovalsTitle), findsOneWidget);
      expect(find.byType(ApprovalCard), findsNWidgets(2));
      expect(find.text('Connection request'), findsOneWidget);
      expect(find.text('Expense claim'), findsOneWidget);
      expect(find.text('Approve'), findsNWidgets(2));
      expect(find.text('Decline'), findsNWidgets(2));
      expect(find.text('Return'), findsOneWidget);
      expect(c.badgeOf(InboxTab.approvals), 0, reason: 'no badge from samples');

      await tester.tap(find.text(TourTexts.done));
      await pumpTour(tester);
      await pumpTour(tester);
      expectClean(rig);
      expect(find.byType(ApprovalCard), findsNothing);
      expect(find.text(TourTexts.sampleTag), findsNothing);
      expect(rig.asked.length, asked, reason: 'no read during the tour');
      expect(await service.isSeen(TourId.inbox), isTrue);
      expect(tester.takeException(), isNull);
    });

    for (final how in _Exit.values) {
      testWidgets('restore runs on ${how.name}, in the middle of Approvals', (
        tester,
      ) async {
        await boot(tester);
        final asked = rig.asked.length;
        await next(tester); // open card
        await next(tester); // views
        await next(tester); // popup open
        expect(tour.demo.isFilterOpen.value, isTrue);
        if (how != _Exit.leaveTab) {
          await next(tester); // Approvals tab
          await next(tester); // filter bar
          expect(rig.controller.tabIndex.value, 1);
        }
        switch (how) {
          case _Exit.finish:
            while (find.text(TourTexts.next).evaluate().isNotEmpty) {
              await next(tester);
            }
            await tester.tap(find.text(TourTexts.done));
          case _Exit.skip:
            await tester.tap(find.text(TourTexts.skip));
          case _Exit.cancel:
            service.cancel();
          case _Exit.leaveTab:
            rig.shell.tab.value = HomeTab.chats;
        }
        await pumpTour(tester);
        await pumpTour(tester);
        expectClean(rig);
        expect(rig.asked.length, asked);
        expect(tester.takeException(), isNull);
        expect(
          await service.isSeen(TourId.inbox),
          how == _Exit.finish || how == _Exit.skip,
        );
      });
    }
  });

  group('real data wins', () {
    testWidgets('real records and real requests are used, samples never', (
      tester,
    ) async {
      await boot(tester, hasRecords: true, hasRequests: true);
      expect(service.isActive.value, isTrue);
      final c = rig.controller;
      final seen = <String>[];
      final records = c.rows.map((r) => r.id).toList();
      final asked = rig.asked.length;
      expect(records, [2, 1]);
      expect(find.text(TourTexts.sampleTag), findsNothing);
      expect(find.text(TourTexts.inboxCardsBody(isSample: false)), findsOne);
      seen.add('cards');

      await next(tester);
      expect(tour.demo.expanded, isEmpty, reason: 'a real card opens');
      expect(c.isCardExpanded('r2'), isTrue);
      await next(tester);
      expect(c.isCardExpanded('r2'), isFalse, reason: 'and closes again');
      await next(tester);
      expect(tour.demo.isFilterOpen.value, isTrue);
      await next(tester);
      expect(c.tabIndex.value, 1);
      await next(tester);
      await next(tester);
      expect(find.text(TourTexts.sampleTag), findsNothing);
      expect(find.text('Real expense claim'), findsOneWidget);
      expect(find.text('Expense claim'), findsNothing);
      expect(c.badgeOf(InboxTab.approvals), 1);
      await tester.tap(find.text(TourTexts.done));
      await pumpTour(tester);
      await pumpTour(tester);
      expectClean(rig);
      expect(c.rows.map((r) => r.id).toList(), records);
      expect(c.badgeOf(InboxTab.approvals), 1);
      expect(rig.asked.length, asked);
    });

    testWidgets('a real record arriving mid-tour replaces the sample cards', (
      tester,
    ) async {
      await boot(tester);
      expect(find.byType(InboxCard), findsNWidgets(2));
      expect(find.text(TourTexts.sampleTag), findsNWidgets(2));
      rig.routes['records.query'] = (_) => queryReply([record(9)]);
      unawaited(rig.controller.load(isSilent: true));
      await pumpTour(tester);
      await pumpTour(tester);
      expect(rig.controller.rows.map((r) => r.id), [9]);
      expect(find.byType(InboxCard), findsOneWidget);
      expect(find.text(TourTexts.sampleTag), findsNothing);
      expect(tester.takeException(), isNull);
      service.cancel();
      await pumpTour(tester);
      expectClean(rig);
    });

    testWidgets('a live event during the tour does not disturb it', (
      tester,
    ) async {
      await boot(tester);
      final asked = rig.asked.length;
      rig.emit('record_updated');
      rig.emit('request_created');
      await pumpTour(tester);
      expect(service.isActive.value, isTrue, reason: 'still running');
      expect(find.byType(InboxCard), findsNWidgets(2));
      expect(rig.controller.badgeOf(InboxTab.approvals), 0);
      expect(tester.takeException(), isNull);
      service.cancel();
      await pumpTour(tester);
      expectClean(rig);
      expect(asked, lessThanOrEqualTo(rig.asked.length));
    });
  });

  group('the sample', () {
    test('begin and end leave nothing; ids never meet a real record', () {
      final d = InboxTourDemo();
      d.begin(isRecords: true, isApprovals: true, now: 1000000);
      expect(d.isDriving, isTrue);
      expect(d.rows.every((r) => r.id < 0), isTrue);
      expect(d.approvals.every((a) => a.id < 0), isTrue);
      d.toggle('r-101');
      d.end();
      d.end();
      expect(d.rows, isEmpty);
      expect(d.approvals, isEmpty);
      expect(d.expanded, isEmpty);
      expect(d.isDriving, isFalse);
    });
  });

  group('small screens', () {
    testWidgets('320 px wide, text x1.5: the whole tour, no exception', (
      tester,
    ) async {
      await boot(tester, width: 320, scale: 1.5);
      expect(service.isActive.value, isTrue);
      for (var i = 0; i < 6; i++) {
        expect(tester.takeException(), isNull, reason: 'step $i');
        await next(tester);
      }
      expect(find.byType(ApprovalCard), findsNWidgets(2));
      service.skip();
      await pumpTour(tester);
      await pumpTour(tester);
      expectClean(rig);
      expect(tester.takeException(), isNull);
    });
  });
}

InboxTourPorts _ports() => InboxTourPorts(
  seed: () => false,
  restore: () {},
  expandFirst: () {},
  collapseFirst: () {},
  openFilter: () {},
  closeFilter: () {},
  showApprovals: () {},
  showRecords: () {},
);
