import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:connectum/features/commands/commands_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/tour/tour_test_support.dart';

void main() {
  late TourService service;
  late CommandsTour tour;
  late bool isOpen;
  late bool hasRows;

  setUp(() {
    isOpen = true;
    hasRows = true;
    service = TourService(userId: () => 'u1', store: memoryStore());
    tour = CommandsTour(
      service: service,
      isListOpen: () => isOpen,
      hasRows: () => hasRows,
    );
  });

  tearDown(() => tour.dispose());

  /// A composer: a list panel with two command rows, a send button, a field.
  Widget screen({bool isInboxInside = true}) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        children: [
          const Spacer(),
          if (!isInboxInside)
            SizedBox(key: tour.inboxKey, height: 40, width: 200),
          Container(
            key: tour.panelKey,
            margin: const EdgeInsets.all(8),
            height: 130,
            child: Column(
              children: [
                if (isInboxInside)
                  SizedBox(
                    key: tour.inboxKey,
                    height: 40,
                    width: double.infinity,
                  ),
                SizedBox(key: tour.viewKey, height: 40, width: double.infinity),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(key: tour.sendKey, width: 40, height: 40),
          ),
        ],
      ),
    ),
  );

  Future<void> typeAndPause(WidgetTester tester) async {
    tour.onTyped();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    await pumpTour(tester);
  }

  testWidgets('starts after a pause with the list open, keyboard up', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(screen());
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await typeAndPause(tester);
    expect(service.activeId, TourId.commands);
    expect(find.text(TourTexts.cmdPanelTitle), findsOneWidget);
    await tester.tap(find.text(TourTexts.next));
    await pumpTour(tester);
    expect(find.text(TourTexts.cmdInboxTitle), findsOneWidget);
    await tester.tap(find.text(TourTexts.next));
    await pumpTour(tester);
    expect(find.text(TourTexts.cmdRunTitle), findsOneWidget);
    expect(find.text(TourTexts.done), findsOneWidget);
    await tester.tap(find.text(TourTexts.done));
    await tester.pump();
    expect(await service.isSeen(TourId.commands), isTrue);
  });

  testWidgets('keeps typing: it waits, and then cancels without marking', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(screen());
    tour.onTyped();
    await tester.pump(const Duration(milliseconds: 500));
    tour.onTyped();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      service.isActive.value,
      isFalse,
      reason: 'each key restarts the wait',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await pumpTour(tester);
    expect(service.activeId, TourId.commands);

    tour.onTyped();
    await tester.pump();
    expect(service.isActive.value, isFalse);
    expect(await service.isSeen(TourId.commands), isFalse);
  });

  testWidgets('after typing cancelled it, it does not come back this time', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(screen());
    await typeAndPause(tester);
    expect(service.isActive.value, isTrue);
    tour.onTyped();
    await tester.pump(const Duration(seconds: 5));
    expect(service.isActive.value, isFalse);

    // The list closes and opens again: now it may.
    isOpen = false;
    tour.onTyped();
    isOpen = true;
    await typeAndPause(tester);
    expect(service.activeId, TourId.commands);
    service.cancel();
    await tester.pump();
  });

  testWidgets('the list closing before it starts: it never starts', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(screen());
    tour.onTyped();
    await tester.pump(const Duration(milliseconds: 300));
    isOpen = false;
    tour.onListChanged();
    await tester.pump(const Duration(seconds: 5));
    expect(service.isActive.value, isFalse);
    expect(await service.isSeen(TourId.commands), isFalse);
  });

  testWidgets('the list closing while it shows ends it, not marked', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(screen());
    await typeAndPause(tester);
    expect(service.isActive.value, isTrue);
    isOpen = false;
    tour.onListChanged();
    await tester.pump();
    expect(service.isActive.value, isFalse);
    expect(await service.isSeen(TourId.commands), isFalse);
  });

  testWidgets('a list with no commands yet is waited for, a few times', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(screen());
    hasRows = false;
    tour.onTyped();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(seconds: 2));
    expect(service.isActive.value, isFalse);
    hasRows = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await pumpTour(tester);
    expect(service.activeId, TourId.commands);
    service.cancel();
    await tester.pump();
  });

  testWidgets('an example row outside the panel is left out', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(screen(isInboxInside: false));
    await typeAndPause(tester);
    expect(service.activeId, TourId.commands);
    await tester.tap(find.text(TourTexts.next));
    await pumpTour(tester);
    // #inbox is not in the panel: the next real row is #view.
    expect(find.text(TourTexts.cmdViewTitle), findsOneWidget);
    service.cancel();
    await tester.pump();
  });

  testWidgets('the example is the one row that really is in the list', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(screen());
    final steps = tour.steps();
    expect(steps.length, 4);
    expect(steps.first.target, tour.panelKey);
    expect(steps.last.target, tour.sendKey);
    expect(tour.rowKeyOf('inbox'), tour.inboxKey);
    expect(tour.rowKeyOf('view'), tour.viewKey);
    expect(tour.rowKeyOf('dm'), isNull);
  });
}
