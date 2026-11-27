import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_step.dart';
import 'package:connectum/core/tour/tour_store.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tour_test_support.dart';

void main() {
  late List<GlobalKey> keys;
  late String? user;
  late bool isBlocked;
  late TourService service;

  List<TourStep> steps([int n = 3]) => [
    for (var i = 0; i < n; i++)
      TourStep(
        target: keys[i],
        icon: Icons.star,
        title: 'Title $i',
        body: 'Body $i',
      ),
  ];

  BuildContext homeContext(WidgetTester tester) =>
      tester.element(find.byKey(keys[0]));

  setUp(() {
    keys = List.generate(3, (_) => GlobalKey());
    user = 'u1';
    isBlocked = false;
    service = TourService(
      userId: () => user,
      store: memoryStore(),
      blockers: [() => isBlocked],
    );
  });

  group('seen flags', () {
    test('are kept per user and reset by tour', () async {
      expect(await service.isSeen(TourId.chatList), isFalse);
      await service.markSeen(TourId.chatList);
      expect(await service.isSeen(TourId.chatList), isTrue);
      user = 'u2';
      expect(await service.isSeen(TourId.chatList), isFalse);
      user = 'u1';
      await service.reset(TourId.chatList);
      expect(await service.isSeen(TourId.chatList), isFalse);
    });

    test('the key holds the user, the tour and its version', () {
      expect(
        TourStore.keyOf('u1', TourId.chatList),
        'tour.u1.chatList.v${TourId.chatList.version}',
      );
      expect(
        TourStore.keyOf('u1', TourId.chatList),
        isNot(TourStore.keyOf('u2', TourId.chatList)),
      );
    });

    test('resetAll clears every tour', () async {
      await service.markSeen(TourId.chatList);
      await service.resetAll();
      expect(await service.isSeen(TourId.chatList), isFalse);
    });
  });

  group('start', () {
    testWidgets('shows the tour and ignores a second one', (tester) async {
      await tester.pumpWidget(TourHarness(keys: keys));
      final first = service.start(
        TourId.chatList,
        steps(),
        context: homeContext(tester),
      );
      final second = await service.start(
        TourId.chatList,
        steps(),
        context: homeContext(tester),
      );
      expect(second, TourStart.busy);
      expect(await first, TourStart.started);
      await pumpTour(tester);
      expect(service.isActive.value, isTrue);
      expect(find.text('Title 0'), findsOneWidget);
      expect(
        await service.start(
          TourId.chatList,
          steps(),
          context: homeContext(tester),
        ),
        TourStart.busy,
      );
      service.cancel();
      await tester.pump();
    });

    testWidgets('an interrupted tour is not marked as seen', (tester) async {
      await tester.pumpWidget(TourHarness(keys: keys));
      await service.start(
        TourId.chatList,
        steps(),
        context: homeContext(tester),
      );
      await pumpTour(tester);
      service.cancel();
      await tester.pump();
      expect(service.isActive.value, isFalse);
      expect(await service.isSeen(TourId.chatList), isFalse);
      expect(find.text('Title 0'), findsNothing);
    });

    testWidgets('fewer than two usable steps do not start or mark', (
      tester,
    ) async {
      await tester.pumpWidget(TourHarness(keys: keys, shown: 1));
      final result = await service.start(
        TourId.chatList,
        steps(),
        context: homeContext(tester),
      );
      expect(result, TourStart.tooFewSteps);
      expect(service.isActive.value, isFalse);
      expect(await service.isSeen(TourId.chatList), isFalse);
    });

    testWidgets('a step the permissions do not allow is left out', (
      tester,
    ) async {
      await tester.pumpWidget(TourHarness(keys: keys, shown: 2));
      final list = [
        steps(2)[0],
        TourStep(
          target: keys[1],
          icon: Icons.star,
          title: 'No',
          body: 'No',
          isAllowed: () => false,
        ),
      ];
      final result = await service.start(
        TourId.chatList,
        list,
        context: homeContext(tester),
      );
      expect(result, TourStart.tooFewSteps);
    });

    testWidgets('does not start when something blocks it', (tester) async {
      await tester.pumpWidget(TourHarness(keys: keys));
      isBlocked = true;
      expect(
        await service.start(
          TourId.chatList,
          steps(),
          context: homeContext(tester),
        ),
        TourStart.blocked,
      );
      expect(await service.isSeen(TourId.chatList), isFalse);
    });

    testWidgets('does not start under a bottom sheet', (tester) async {
      await tester.pumpWidget(TourHarness(keys: keys));
      final context = homeContext(tester);
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => const SizedBox(height: 100),
      );
      await tester.pumpAndSettle();
      expect(
        await service.start(TourId.chatList, steps(), context: context),
        TourStart.blocked,
      );
    });

    testWidgets('does not start while the keyboard is up', (tester) async {
      await tester.pumpWidget(TourHarness(keys: keys));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(
        await service.start(
          TourId.chatList,
          steps(),
          context: homeContext(tester),
        ),
        TourStart.blocked,
      );
    });

    testWidgets('without a signed-in user it does not start', (tester) async {
      await tester.pumpWidget(TourHarness(keys: keys));
      user = null;
      expect(
        await service.start(
          TourId.chatList,
          steps(),
          context: homeContext(tester),
        ),
        TourStart.blocked,
      );
    });

    testWidgets('a seen tour does not start again', (tester) async {
      await tester.pumpWidget(TourHarness(keys: keys));
      await service.markSeen(TourId.chatList);
      expect(
        await service.start(
          TourId.chatList,
          steps(),
          context: homeContext(tester),
        ),
        TourStart.seen,
      );
    });
  });

  group('ending', () {
    testWidgets('Skip marks the tour as seen', (tester) async {
      await tester.pumpWidget(TourHarness(keys: keys));
      await service.start(
        TourId.chatList,
        steps(),
        context: homeContext(tester),
      );
      await pumpTour(tester);
      await tester.tap(find.text(TourTexts.skip));
      await tester.pump();
      expect(service.isActive.value, isFalse);
      expect(await service.isSeen(TourId.chatList), isTrue);
    });

    testWidgets('Next to the last step marks the tour as seen', (tester) async {
      await tester.pumpWidget(TourHarness(keys: keys));
      await service.start(
        TourId.chatList,
        steps(),
        context: homeContext(tester),
      );
      await pumpTour(tester);
      for (var i = 0; i < 2; i++) {
        expect(find.text('Title $i'), findsOneWidget);
        await tester.tap(find.text(TourTexts.next));
        await pumpTour(tester);
      }
      expect(find.text(TourTexts.done), findsOneWidget);
      await tester.tap(find.text(TourTexts.done));
      await tester.pump();
      expect(service.isActive.value, isFalse);
      expect(await service.isSeen(TourId.chatList), isTrue);
    });

    testWidgets('a tap on the scrim does nothing', (tester) async {
      await tester.pumpWidget(TourHarness(keys: keys));
      await service.start(
        TourId.chatList,
        steps(),
        context: homeContext(tester),
      );
      await pumpTour(tester);
      await tester.tapAt(const Offset(390, 590));
      await pumpTour(tester);
      expect(find.text('Title 0'), findsOneWidget);
      expect(service.isActive.value, isTrue);
      service.cancel();
      await tester.pump();
    });

    testWidgets('a sheet opening on top ends it without marking it', (
      tester,
    ) async {
      await tester.pumpWidget(TourHarness(keys: keys));
      final context = homeContext(tester);
      await service.start(TourId.chatList, steps(), context: context);
      await pumpTour(tester);
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => const SizedBox(height: 100),
      );
      await pumpTour(tester);
      expect(service.isActive.value, isFalse);
      expect(await service.isSeen(TourId.chatList), isFalse);
    });
  });
}
