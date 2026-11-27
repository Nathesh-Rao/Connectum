import 'dart:async';
import 'dart:io';

import 'package:connectum/core/tour/tour_action.dart';
import 'package:connectum/core/tour/tour_demo.dart';
import 'package:connectum/core/tour/tour_gesture.dart';
import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_step.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:connectum/core/tour/widgets/tour_pointer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tour_test_support.dart';

/// A fake screen state: what the tour's actions and sample change, and what
/// must be back to normal at the end.
class _Screen {
  int seeds = 0;
  int restores = 0;
  bool hasSample = false;
  bool isSelected = false;
  bool isOpen = false;
  bool hasRealItems = false;
  bool throwsOnRun = false;
  final log = <String>[];

  TourDemo get demo => TourDemo(
    seed: () {
      seeds++;
      if (hasRealItems) return false;
      hasSample = true;
      return true;
    },
    restore: () {
      restores++;
      hasSample = false;
    },
  );

  TourAction select({String? carry}) => TourAction(
    kind: TourActionKind.selectMessage,
    carry: carry,
    run: () {
      log.add('select');
      isSelected = true;
      if (throwsOnRun) throw StateError('boom');
    },
    undo: () {
      log.add('unselect');
      isSelected = false;
    },
  );

  TourAction drawer() => TourAction(
    kind: TourActionKind.openDrawer,
    run: () {
      log.add('open');
      isOpen = true;
    },
    undo: () {
      log.add('close');
      isOpen = false;
    },
  );

  bool get isClean => !hasSample && !isSelected && !isOpen;
}

/// Starts [start] and pumps frames until it answers (a tour with a sample
/// waits one frame after the sample goes in).
Future<TourStart> startPumped(
  WidgetTester tester,
  Future<TourStart> Function() start,
) async {
  TourStart? result;
  final done = start().then((r) => result = r);
  for (var i = 0; i < 20 && result == null; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await done;
  return result!;
}

void main() {
  late List<GlobalKey> keys;
  late _Screen screen;
  late TourService service;

  List<TourStep> steps() => [
    TourStep(
      target: keys[0],
      icon: Icons.info,
      title: 'A',
      body: 'a',
      actions: [screen.select(carry: 'sel')],
    ),
    TourStep(
      target: keys[1],
      icon: Icons.info,
      title: 'B',
      body: 'b',
      actions: [
        screen.select(carry: 'sel'),
        screen.drawer(),
      ],
    ),
    TourStep(target: keys[2], icon: Icons.info, title: 'C', body: 'c'),
  ];

  setUp(() {
    keys = [GlobalKey(), GlobalKey(), GlobalKey()];
    screen = _Screen();
    service = TourService(userId: () => 'u1', store: memoryStore());
  });

  Future<void> begin(WidgetTester tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(TourHarness(keys: keys));
    final context = tester.element(find.byKey(keys[0]));
    final result = await startPumped(
      tester,
      () => service.start(
        TourId.commands,
        steps(),
        context: context,
        demo: screen.demo,
      ),
    );
    expect(result, TourStart.started);
    await pumpTour(tester);
  }

  group('restore runs on every way out', () {
    testWidgets('finishing the tour', (tester) async {
      await begin(tester);
      expect(screen.hasSample, isTrue);
      expect(screen.isSelected, isTrue);
      await tester.tap(find.text(TourTexts.next));
      await pumpTour(tester);
      expect(screen.isOpen, isTrue);
      await tester.tap(find.text(TourTexts.next));
      await pumpTour(tester);
      expect(screen.isOpen, isFalse, reason: 'left step B');
      await tester.tap(find.text(TourTexts.done));
      await pumpTour(tester);
      expect(screen.isClean, isTrue);
      expect(screen.restores, 1);
      expect(await service.isSeen(TourId.commands), isTrue);
    });

    testWidgets('skipping', (tester) async {
      await begin(tester);
      await tester.tap(find.text(TourTexts.skip));
      await pumpTour(tester);
      expect(screen.isClean, isTrue);
      expect(screen.restores, 1);
      expect(await service.isSeen(TourId.commands), isTrue);
    });

    testWidgets('back (the screen cancels the tour)', (tester) async {
      await begin(tester);
      service.cancel();
      await tester.pump();
      expect(screen.isClean, isTrue);
      expect(screen.restores, 1);
      expect(await service.isSeen(TourId.commands), isFalse);
    });

    testWidgets('app pause', (tester) async {
      await begin(tester);
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(screen.isClean, isTrue);
      expect(screen.restores, 1);
    });

    testWidgets('a route change', (tester) async {
      await begin(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(builder: (_) => const Placeholder()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(service.isActive.value, isFalse);
      expect(screen.isClean, isTrue);
      expect(screen.restores, 1);
    });

    testWidgets('the screen closing', (tester) async {
      await begin(tester);
      service.onClose();
      await tester.pump();
      expect(screen.isClean, isTrue);
      expect(screen.restores, 1);
    });

    testWidgets('an action that throws still ends clean', (tester) async {
      screen.throwsOnRun = true;
      await begin(tester);
      expect(service.isActive.value, isTrue, reason: 'the error is logged');
      await tester.tap(find.text(TourTexts.skip));
      await pumpTour(tester);
      expect(screen.isClean, isTrue);
      expect(screen.restores, 1);
    });

    testWidgets('a tour that does not start puts the sample back', (
      tester,
    ) async {
      useTallScreen(tester);
      // Only one target on screen: too few steps after the sample went in.
      await tester.pumpWidget(TourHarness(keys: keys, shown: 1));
      final context = tester.element(find.byKey(keys[0]));
      final result = await startPumped(
        tester,
        () => service.start(
          TourId.commands,
          [
            for (var i = 0; i < 3; i++)
              TourStep(
                target: keys[i],
                icon: Icons.info,
                title: 'A',
                body: 'a',
              ),
          ],
          context: context,
          demo: screen.demo,
        ),
      );
      expect(result, TourStart.tooFewSteps);
      expect(screen.seeds, 1);
      expect(screen.restores, 1);
      expect(screen.isClean, isTrue);
    });
  });

  group('steps', () {
    testWidgets('an action is undone when the person leaves its step', (
      tester,
    ) async {
      await begin(tester);
      expect(screen.log, ['select']);
      await tester.tap(find.text(TourTexts.next));
      await pumpTour(tester);
      // The selection is carried from A to B: not undone, not repeated.
      expect(screen.log, ['select', 'open']);
      await tester.tap(find.text(TourTexts.next));
      await pumpTour(tester);
      expect(screen.log, ['select', 'open', 'close', 'unselect']);
      service.cancel();
      await tester.pump();
    });

    testWidgets('the spotlight waits for the action to settle', (tester) async {
      await begin(tester);
      expect(find.text('A'), findsOneWidget);
      await tester.tap(find.text(TourTexts.next));
      // The action has run and the step has not changed yet.
      await tester.pump();
      expect(screen.isOpen, isTrue);
      await pumpTour(tester);
      expect(find.text('B'), findsOneWidget);
      service.cancel();
      await tester.pump();
    });
  });

  group('real data first', () {
    testWidgets('no sample goes in when the screen has real items', (
      tester,
    ) async {
      screen.hasRealItems = true;
      await begin(tester);
      expect(screen.seeds, 1);
      expect(screen.hasSample, isFalse);
      // UI-state actions on the real item still run.
      expect(screen.isSelected, isTrue);
      service.cancel();
      await tester.pump();
      expect(screen.isClean, isTrue);
    });
  });

  group('the pointer', () {
    testWidgets('with reduce-motion on it draws nothing and returns at once', (
      tester,
    ) async {
      final controller = TourPointerController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TourPointer(controller: controller)),
        ),
      );
      await controller.play(
        const Rect.fromLTWH(10, 10, 100, 40),
        TourGesture.tap,
        isReduced: true,
      );
      expect(controller.plays, 0);
      expect(controller.isShown, isFalse);
    });

    testWidgets('with motion on it moves, plays the gesture and fades', (
      tester,
    ) async {
      final controller = TourPointerController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TourPointer(controller: controller)),
        ),
      );
      for (final g in [
        TourGesture.tap,
        TourGesture.longPress,
        TourGesture.swipeRight,
      ]) {
        var isDone = false;
        controller
            .play(const Rect.fromLTWH(40, 200, 200, 48), g, isReduced: false)
            .then((_) => isDone = true);
        for (var i = 0; i < 40 && !isDone; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(isDone, isTrue, reason: '$g');
        expect(controller.lastGesture, g);
        expect(controller.isShown, isTrue);
      }
      expect(controller.plays, 3);
      unawaited(controller.hide());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.isShown, isFalse);
    });

    testWidgets('it takes no touch, so Next and Skip stay usable', (
      tester,
    ) async {
      final controller = TourPointerController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TourPointer(controller: controller)),
        ),
      );
      unawaited(
        controller.play(
          const Rect.fromLTWH(0, 0, 100, 40),
          TourGesture.tap,
          isReduced: false,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.descendant(
          of: find.byType(TourPointer),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    });
  });

  group('isolation', () {
    test('the tour code imports no repository, database or socket', () {
      final files = [
        'lib/core/tour/tour_action.dart',
        'lib/core/tour/tour_demo.dart',
        'lib/core/tour/tour_runner.dart',
        'lib/core/tour/widgets/tour_pointer.dart',
        'lib/features/conversation/conversation_tour_demo.dart',
        'lib/features/conversation/widgets/conversation_sample_row.dart',
        'lib/features/workspace/workspace_tour_demo.dart',
        'lib/features/workspace/widgets/workspace_sample_row.dart',
      ];
      final banned = RegExp(
        r"import '[^']*(repositories|/db/|socket|outbox|notifications|search|log_viewer|get/get_connect)[^']*';",
      );
      for (final f in files) {
        final text = File(f).readAsStringSync();
        expect(banned.hasMatch(text), isFalse, reason: f);
        expect(text.contains('Get.find'), isFalse, reason: f);
        expect(text.contains('Get.put'), isFalse, reason: f);
      }
    });
  });
}
