import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_trigger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int calls;
  late bool canTry;
  late List<TourStart> answers;
  late TourTrigger trigger;

  // The last answer repeats.
  TourTrigger make({int maxTries = 20}) => TourTrigger(
    canTry: () => canTry,
    start: () async {
      final i = calls++;
      return answers[i < answers.length ? i : answers.length - 1];
    },
    maxTries: maxTries,
  );

  setUp(() {
    calls = 0;
    canTry = true;
    answers = [TourStart.started];
    trigger = make();
  });

  tearDown(() => trigger.dispose());

  testWidgets('waits 0.8 s before the first try', (tester) async {
    trigger.schedule();
    await tester.pump(const Duration(milliseconds: 700));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 150));
    expect(calls, 1);
    expect(trigger.hasStarted, isTrue);
  });

  testWidgets('waits while blocked, retrying every 2 s', (tester) async {
    answers = [TourStart.blocked, TourStart.tooFewSteps, TourStart.started];
    trigger.schedule();
    await tester.pump(const Duration(milliseconds: 800));
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 1900));
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 150));
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 3);
    expect(trigger.hasStarted, isTrue);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 3);
  });

  testWidgets('starts once: a second schedule does not start it again', (
    tester,
  ) async {
    trigger.schedule();
    trigger.schedule();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    trigger.schedule();
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 1);
  });

  testWidgets('gives up after 20 tries', (tester) async {
    answers = [TourStart.blocked];
    trigger.schedule();
    await tester.pump(const Duration(milliseconds: 800));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(calls, 20);
    expect(trigger.hasStarted, isFalse);
  });

  testWidgets('busy keeps retrying with no limit until it starts', (
    tester,
  ) async {
    answers = [TourStart.busy];
    trigger.schedule();
    await tester.pump(const Duration(milliseconds: 800));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    expect(calls, greaterThan(40));
    answers = [TourStart.started];
    await tester.pump(const Duration(seconds: 2));
    expect(trigger.hasStarted, isTrue);
  });

  testWidgets('a busy retry stops when the screen is left', (tester) async {
    answers = [TourStart.busy];
    trigger.schedule();
    await tester.pump(const Duration(seconds: 5));
    final before = calls;
    expect(before, greaterThan(1));
    trigger.cancel();
    await tester.pump(const Duration(seconds: 20));
    expect(calls, before);
  });

  testWidgets('a busy retry stops when the screen cannot try any more', (
    tester,
  ) async {
    answers = [TourStart.busy];
    trigger.schedule();
    await tester.pump(const Duration(seconds: 5));
    canTry = false;
    await tester.pump(const Duration(seconds: 3));
    final before = calls;
    await tester.pump(const Duration(seconds: 20));
    expect(calls, before);
  });

  testWidgets('does nothing while the screen cannot try', (tester) async {
    canTry = false;
    trigger.schedule();
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 0);
    canTry = true;
    trigger.schedule();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
  });

  testWidgets('a seen tour, a failure or a tour that must wait end it', (
    tester,
  ) async {
    for (final end in [TourStart.seen, TourStart.failed, TourStart.notReady]) {
      calls = 0;
      answers = [end, TourStart.started];
      final t = make()..schedule();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1, reason: end.name);
      expect(t.isDone, isTrue, reason: end.name);
      await tester.pump(const Duration(seconds: 10));
      t.schedule();
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 1, reason: end.name);
      t.dispose();
    }
  });

  testWidgets('cancel stops waiting and allows a fresh start', (tester) async {
    trigger.schedule();
    trigger.cancel();
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 0);
    trigger.schedule();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    trigger.cancel();
    trigger.schedule();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
  });

  testWidgets('a start that throws ends it without throwing', (tester) async {
    final t = TourTrigger(
      canTry: () => true,
      start: () async {
        calls++;
        throw StateError('boom');
      },
    )..schedule();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    expect(t.isDone, isTrue);
    expect(tester.takeException(), isNull);
    t.dispose();
  });

  testWidgets('a disposed trigger never tries', (tester) async {
    trigger.schedule();
    trigger.dispose();
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 0);
  });
}
