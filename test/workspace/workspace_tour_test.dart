import 'package:connectum/core/selection/message_selection.dart';
import 'package:connectum/core/selection/selection_rules.dart';
import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:connectum/core/widgets/message_selection/selectable_row.dart';
import 'package:connectum/core/widgets/message_selection/selection_app_bar.dart';
import 'package:connectum/features/workspace/widgets/workspace_sample_row.dart';
import 'package:connectum/features/workspace/workspace_tour.dart';
import 'package:connectum/features/workspace/workspace_tour_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../core/tour/tour_demo_test.dart' show startPumped;
import '../core/tour/tour_test_support.dart';

/// The Work Space parts the tour touches, from the real widgets: the header
/// switcher with the selection bar, the feed with the sample note (or one real
/// note) and the composer. There is no reaction bar in the Work Space.
class _Workspace extends StatelessWidget {
  const _Workspace({
    required this.tour,
    required this.realSelection,
    required this.hasReal,
    this.scale = 1,
  });

  final WorkspaceTour tour;
  final MessageSelection realSelection;
  final bool hasReal;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final demo = tour.demo;
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Obx(() {
          final selection = demo.isOn.value ? demo.selection : realSelection;
          return Column(
            children: [
              SelectionHeaderSwitcher(
                isSelecting: demo.selection.isActive || realSelection.isActive,
                selectionBar: KeyedSubtree(
                  key: tour.selectionBarKey,
                  child: SelectionAppBar(
                    count: selection.ids.length,
                    onExit: () {},
                    items: [
                      for (final a in SelectionRules.available([
                        WorkspaceTourDemo.target,
                      ]))
                        SelectionBarItem(
                          action: a,
                          icon: Icons.circle,
                          label: a.name,
                          onTap: () {},
                        ),
                    ],
                  ),
                ),
                header: KeyedSubtree(
                  key: tour.headerKey,
                  child: const SizedBox(height: 56, width: double.infinity),
                ),
              ),
              Expanded(
                child: KeyedSubtree(
                  key: tour.areaKey,
                  child: ListView(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (demo.isOn.value) WorkspaceSampleRow(tour: tour),
                      if (hasReal)
                        SelectableRow(
                          selection: realSelection,
                          id: 'real-1',
                          swipeKey: tour.swipeKey,
                          onSwipeReply: () {},
                          child: KeyedSubtree(
                            key: tour.noteKey,
                            child: const SizedBox(
                              height: 44,
                              child: Text('a real note'),
                            ),
                          ),
                        ),
                      const Text('Welcome'),
                    ],
                  ),
                ),
              ),
              KeyedSubtree(
                key: tour.composerKey,
                child: const SizedBox(height: 56, width: double.infinity),
              ),
            ],
          );
        }),
      ),
    );
  }
}

void main() {
  late WorkspaceTour tour;
  late TourService service;
  late MessageSelection real;

  setUp(() {
    service = TourService(userId: () => 'u1', store: memoryStore());
    tour = WorkspaceTour(service: service);
    real = MessageSelection();
  });

  group('the steps', () {
    test('five at most, in screen order', () {
      final steps = tour.steps(hasNote: false);
      expect(steps.map((s) => s.title), [
        TourTexts.wsHeaderTitle,
        TourTexts.wsComposerTitle,
        TourTexts.wsSwipeTitle,
        TourTexts.wsHoldTitle,
        TourTexts.wsOptionsTitle,
      ]);
      expect(steps[2].actions.single.kind.name, 'swipeRow');
      expect(steps[3].actions.single.carry, steps[4].actions.single.carry);
    });

    test('the options copy names exactly what the note bar offers', () {
      final options = tour.steps(hasNote: false).last;
      expect(
        options.body,
        'The bar shows Reply, Save and Delete. More has Copy, Pin and Edit. '
        'A note can be edited at any time.',
      );
      // Reactions and forwarding do not exist for notes.
      final all = tour
          .steps(hasNote: false)
          .map((s) => '${s.title} ${s.body}')
          .join(' ');
      expect(all, isNot(contains('react')));
      expect(all, isNot(contains('Forward')));
      expect(all, isNot(contains('15')));
    });

    test('with a note on screen they point at it, else at the sample', () {
      expect(tour.steps(hasNote: true)[3].target, tour.noteKey);
      expect(tour.steps(hasNote: false)[3].target, tour.noteKey);
    });
  });

  group('the sample', () {
    test('it seeds only when there is no note, and restores', () {
      tour.demo.prepare(hasRealNote: true);
      expect(tour.demo.seed(), isFalse);
      expect(tour.demo.isOn.value, isFalse);
      tour.demo.prepare(hasRealNote: false);
      expect(tour.demo.seed(), isTrue);
      expect(tour.demo.note!.isMine, isTrue);
      tour.demo.select();
      expect(tour.demo.selectedNotes.single.msgId, WorkspaceTourDemo.noteId);
      tour.demo.restore();
      tour.demo.restore();
      expect(tour.demo.isOn.value, isFalse);
      expect(tour.demo.note, isNull);
      expect(tour.demo.selection.isActive, isFalse);
    });
  });

  group('on screen', () {
    Future<TourStart> go(WidgetTester tester, {required bool hasNote}) async {
      await service.markSeen(TourId.chatList);
      return startPumped(
        tester,
        () => tour.start(
          hasNote: hasNote,
          holdId: hasNote ? 'real-1' : null,
          target: hasNote ? WorkspaceTourDemo.target : null,
          select: real.onLongPress,
          clear: real.clear,
        ),
      );
    }

    Future<void> next(WidgetTester tester, [String? label]) async {
      await tester.tap(find.text(label ?? TourTexts.next));
      await pumpTour(tester);
      await pumpTour(tester);
    }

    testWidgets('an empty Work Space shows one tagged sample note', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        _Workspace(tour: tour, realSelection: real, hasReal: false),
      );
      expect(await tour.start(hasNote: false), TourStart.notReady);
      expect(await go(tester, hasNote: false), TourStart.started);
      await pumpTour(tester);
      expect(find.text(TourTexts.sampleTag), findsOneWidget);
      expect(find.text(TourTexts.sampleNote), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(WorkspaceSampleRow),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
      await next(tester); // composer
      final restX = tester.getTopLeft(find.text(TourTexts.sampleNote)).dx;
      await next(tester); // swipe
      expect(find.text(TourTexts.wsSwipeTitle), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(TourTexts.sampleNote)).dx,
        greaterThan(restX + 20),
      );
      await next(tester); // hold
      expect(find.text(TourTexts.wsHoldTitle), findsOneWidget);
      expect(tour.demo.selection.isActive, isTrue);
      expect(real.isActive, isFalse);
      await next(tester); // options
      expect(find.text(TourTexts.wsOptionsTitle), findsOneWidget);
      expect(find.byType(SelectionAppBar), findsOneWidget);
      await next(tester, TourTexts.done);
      expect(service.isActive.value, isFalse);
      expect(tour.demo.isOn.value, isFalse);
      expect(tour.demo.selection.isActive, isFalse);
      expect(find.text(TourTexts.sampleTag), findsNothing);
      expect(await service.isSeen(TourId.workspace), isTrue);
    });

    testWidgets('a Work Space with a note uses it and shows no sample', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        _Workspace(tour: tour, realSelection: real, hasReal: true),
      );
      expect(await go(tester, hasNote: true), TourStart.started);
      await pumpTour(tester);
      expect(tour.demo.isOn.value, isFalse);
      expect(find.text(TourTexts.sampleTag), findsNothing);
      await next(tester);
      await next(tester); // swipe
      await next(tester); // hold: the real selection opens
      expect(real.ids.single, 'real-1');
      expect(tour.demo.selection.isActive, isFalse);
      await next(tester); // options
      await next(tester, TourTexts.done);
      expect(real.isActive, isFalse);
      expect(find.text('a real note'), findsOneWidget);
    });

    testWidgets('skipping puts the sample and the selection back', (
      tester,
    ) async {
      useTallScreen(tester);
      await tester.pumpWidget(
        _Workspace(tour: tour, realSelection: real, hasReal: false),
      );
      expect(await go(tester, hasNote: false), TourStart.started);
      await pumpTour(tester);
      await next(tester);
      await next(tester);
      await next(tester);
      expect(tour.demo.selection.isActive, isTrue);
      await tester.tap(find.text(TourTexts.skip));
      await pumpTour(tester);
      expect(tour.demo.isOn.value, isFalse);
      expect(tour.demo.selection.isActive, isFalse);
    });

    for (final scale in [1.0, 1.5]) {
      testWidgets('320 px wide at ${scale}x text, with the sample', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadAppFont();
        await tester.pumpWidget(
          _Workspace(
            tour: tour,
            realSelection: real,
            hasReal: false,
            scale: scale,
          ),
        );
        expect(await go(tester, hasNote: false), TourStart.started);
        await pumpTour(tester);
        for (var i = 0; i < 5; i++) {
          final label = i == 4 ? TourTexts.done : TourTexts.next;
          expect(find.text(label), findsOneWidget, reason: 'step $i');
          final rect = tester.getRect(find.text(label));
          expect(rect.left, greaterThanOrEqualTo(0), reason: 'step $i');
          expect(rect.right, lessThanOrEqualTo(320), reason: 'step $i');
          expect(tester.takeException(), isNull, reason: 'step $i');
          await tester.tap(find.text(label));
          await pumpTour(tester);
          await pumpTour(tester);
        }
        expect(service.isActive.value, isFalse);
      });
    }
  });
}
