import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:connectum/features/chats/chats_tour.dart';
import 'package:connectum/features/home_shell/home_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/tour/tour_test_support.dart';

/// The chat list: the header's two targets, the search, the pinned My Work
/// Space row, the new chat button and the bottom bar. [hasChats] adds a row.
/// No empty-state widget is a tour target any more.
Widget _chatList(
  ChatsTour tour,
  GlobalKey navKey, {
  required bool hasChats,
  double scale = 1,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: true, textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        children: [
          KeyedSubtree(
            key: tour.headerKey,
            child: Row(
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: tour.switcherKey,
                    child: const SizedBox(height: 56),
                  ),
                ),
                KeyedSubtree(
                  key: tour.actionsKey,
                  child: const SizedBox(height: 56, width: 100),
                ),
              ],
            ),
          ),
          KeyedSubtree(
            key: tour.searchKey,
            child: const SizedBox(height: 44, width: double.infinity),
          ),
          KeyedSubtree(
            key: tour.workspaceKey,
            child: const SizedBox(height: 64, width: double.infinity),
          ),
          Expanded(
            child: Stack(
              children: [
                if (hasChats)
                  Align(
                    alignment: Alignment.topCenter,
                    child: KeyedSubtree(
                      key: tour.firstRowKey,
                      child: const SizedBox(height: 64, width: double.infinity),
                    ),
                  ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: KeyedSubtree(
                    key: tour.newChatKey,
                    child: const SizedBox(width: 56, height: 56),
                  ),
                ),
              ],
            ),
          ),
          KeyedSubtree(
            key: navKey,
            child: const SizedBox(height: 64, width: double.infinity),
          ),
        ],
      ),
    ),
  );
}

ChatsTour _tour(GlobalKey navKey, [TourService? service]) => ChatsTour(
  service: service ?? TourService(userId: () => 'u1', store: memoryStore()),
  tabsKey: navKey,
);

void main() {
  group('the steps', () {
    test('with no chats there is no chat step and no empty-state step', () {
      final tour = _tour(GlobalKey());
      final steps = tour.steps(isEmpty: true);
      expect(steps.map((s) => s.title), [
        TourTexts.chatSwitcherTitle,
        TourTexts.chatActionsTitle,
        TourTexts.chatSearchTitle,
        TourTexts.chatWorkspaceTitle,
        TourTexts.chatNewTitle,
        TourTexts.chatTabsTitle,
      ]);
      expect(steps.map((s) => s.target), isNot(contains(tour.firstRowKey)));
    });

    test('with chats the long-press step is kept and My Work Space added', () {
      final tour = _tour(GlobalKey());
      final steps = tour.steps(isEmpty: false);
      expect(steps.map((s) => s.title), [
        TourTexts.chatSwitcherTitle,
        TourTexts.chatActionsTitle,
        TourTexts.chatSearchTitle,
        TourTexts.chatWorkspaceTitle,
        TourTexts.chatRowTitle,
        TourTexts.chatNewTitle,
        TourTexts.chatTabsTitle,
      ]);
      final row = steps.firstWhere((s) => s.title == TourTexts.chatRowTitle);
      expect(row.target, tour.firstRowKey);
      expect(row.body, TourTexts.chatRowBody);
    });

    test('the header is two steps: the switcher, then the bell and avatar', () {
      final tour = _tour(GlobalKey());
      final steps = tour.steps(isEmpty: true);
      expect(steps[0].target, tour.switcherKey);
      expect(steps[1].target, tour.actionsKey);
      expect(steps[3].target, tour.workspaceKey);
    });

    test('the tabs line names every available tab and no other', () {
      expect(
        TourTexts.chatTabsBody([for (final t in HomeTab.values) t.label]),
        'Switch between Chats, Smart view, Inbox, Agents and Submits down here.',
      );
      expect(
        TourTexts.chatTabsBody(['Chats', 'Inbox']),
        'Switch between Chats and Inbox down here.',
      );
    });
  });

  group('on screen', () {
    Future<void> runAll(
      WidgetTester tester,
      ChatsTour tour,
      List<String> titles,
      TourService service, {
      required bool isEmpty,
    }) async {
      expect(await tour.start(isEmpty: isEmpty), TourStart.started);
      await pumpTour(tester);
      for (var i = 0; i < titles.length; i++) {
        expect(find.text(titles[i]), findsOneWidget, reason: 'step $i');
        await tester.tap(
          find.text(i == titles.length - 1 ? TourTexts.done : TourTexts.next),
        );
        await pumpTour(tester);
      }
      expect(service.isActive.value, isFalse);
      expect(await service.isSeen(TourId.chatList), isTrue);
    }

    testWidgets('zero chats: six steps, ending on the bottom bar', (
      tester,
    ) async {
      useTallScreen(tester);
      final navKey = GlobalKey();
      final service = TourService(userId: () => 'u1', store: memoryStore());
      final tour = _tour(navKey, service);
      await tester.pumpWidget(_chatList(tour, navKey, hasChats: false));
      await runAll(
        tester,
        tour,
        [
          TourTexts.chatSwitcherTitle,
          TourTexts.chatActionsTitle,
          TourTexts.chatSearchTitle,
          TourTexts.chatWorkspaceTitle,
          TourTexts.chatNewTitle,
          TourTexts.chatTabsTitle,
        ],
        service,
        isEmpty: true,
      );
    });

    testWidgets('with chats: seven steps, My Work Space then the row', (
      tester,
    ) async {
      useTallScreen(tester);
      final navKey = GlobalKey();
      final service = TourService(userId: () => 'u1', store: memoryStore());
      final tour = _tour(navKey, service);
      await tester.pumpWidget(_chatList(tour, navKey, hasChats: true));
      await runAll(
        tester,
        tour,
        [
          TourTexts.chatSwitcherTitle,
          TourTexts.chatActionsTitle,
          TourTexts.chatSearchTitle,
          TourTexts.chatWorkspaceTitle,
          TourTexts.chatRowTitle,
          TourTexts.chatNewTitle,
          TourTexts.chatTabsTitle,
        ],
        service,
        isEmpty: false,
      );
    });

    testWidgets('the row step is left out while its target does not exist', (
      tester,
    ) async {
      useTallScreen(tester);
      final navKey = GlobalKey();
      final service = TourService(userId: () => 'u1', store: memoryStore());
      final tour = _tour(navKey, service);
      await tester.pumpWidget(_chatList(tour, navKey, hasChats: false));
      // Asking for the chats version with no row on screen: six steps remain.
      expect(await tour.start(isEmpty: false), TourStart.started);
      await pumpTour(tester);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text(TourTexts.next));
        await pumpTour(tester);
      }
      expect(find.text(TourTexts.done), findsOneWidget);
      service.cancel();
      await tester.pump();
    });

    for (final scale in [1.0, 1.5]) {
      testWidgets('320 px wide at ${scale}x text: every card fits', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadAppFont();
        final navKey = GlobalKey();
        final service = TourService(userId: () => 'u1', store: memoryStore());
        final tour = _tour(navKey, service);
        await tester.pumpWidget(
          _chatList(tour, navKey, hasChats: true, scale: scale),
        );
        expect(await tour.start(isEmpty: false), TourStart.started);
        await pumpTour(tester);
        for (var i = 0; i < 7; i++) {
          final label = i == 6 ? TourTexts.done : TourTexts.next;
          expect(find.text(label), findsOneWidget, reason: 'step $i');
          final rect = tester.getRect(find.text(label));
          expect(rect.left, greaterThanOrEqualTo(0), reason: 'step $i');
          expect(rect.right, lessThanOrEqualTo(320), reason: 'step $i');
          expect(tester.takeException(), isNull, reason: 'step $i');
          await tester.tap(find.text(label));
          await pumpTour(tester);
        }
        expect(service.isActive.value, isFalse);
      });
    }
  });
}
