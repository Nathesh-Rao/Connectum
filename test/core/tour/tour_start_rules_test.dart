import 'package:connectum/core/log/app_log.dart';
import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_step.dart';
import 'package:connectum/core/tour/tour_trigger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tour_test_support.dart';

void main() {
  late List<GlobalKey> keys;
  late DateTime clock;
  late String route;
  late TourService service;
  late List<String> logs;

  List<TourStep> steps() => [
    for (var i = 0; i < 3; i++)
      TourStep(target: keys[i], icon: Icons.star, title: 'T$i', body: 'B$i'),
  ];

  setUp(() {
    keys = List.generate(3, (_) => GlobalKey());
    clock = DateTime(2026, 11, 26, 9);
    route = AppRoutes.chats;
    logs = [];
    AppLog.sink = logs.add;
    service = TourService(
      userId: () => 'u1',
      store: memoryStore(),
      now: () => clock,
      route: () => route,
    );
  });

  tearDown(() => AppLog.sink = null);

  Future<TourStart> start(WidgetTester tester, TourId id, {TourId? after}) =>
      service.start(
        id,
        steps(),
        context: tester.element(find.byKey(keys[0])),
        after: after ?? (id == TourId.chatList ? null : TourId.chatList),
      );

  Future<void> finishChatList(WidgetTester tester) async {
    route = AppRoutes.chats;
    expect(await start(tester, TourId.chatList), TourStart.started);
    await pumpTour(tester);
    service.skip();
    await tester.pump();
  }

  testWidgets('chat tour starts in a conversation after chatList was done', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(TourHarness(keys: keys));
    await finishChatList(tester);
    clock = clock.add(const Duration(seconds: 95));
    route = '/conversation/42';
    expect(await start(tester, TourId.chat), TourStart.started);
    await pumpTour(tester);
    service.cancel();
    await tester.pump();
  });

  for (final r in [
    AppRoutes.workspace,
    AppRoutes.profile,
    AppRoutes.notifications,
    AppRoutes.smartView,
    AppRoutes.inbox,
  ]) {
    testWidgets('a tour starts from its own route $r', (tester) async {
      useTallScreen(tester);
      await tester.pumpWidget(TourHarness(keys: keys));
      await finishChatList(tester);
      clock = clock.add(const Duration(seconds: 95));
      route = r;
      expect(await start(tester, TourId.workspace), TourStart.started);
      await pumpTour(tester);
      service.cancel();
      await tester.pump();
    });
  }

  testWidgets('join, sign-in and onboarding routes still block', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(TourHarness(keys: keys));
    for (final r in [
      AppRoutes.onboarding,
      AppRoutes.authentication,
      AppRoutes.verification,
      AppRoutes.enterprises,
    ]) {
      route = r;
      expect(
        await start(tester, TourId.chatList),
        TourStart.blocked,
        reason: r,
      );
    }
    expect(logs.last, contains('tour:chatList start -> blocked:route:'));
  });

  testWidgets('after chatList, every other tour starts straight away', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(TourHarness(keys: keys));
    await finishChatList(tester);
    for (final id in [
      TourId.chat,
      TourId.workspace,
      TourId.smartView,
      TourId.inbox,
      TourId.notifications,
      TourId.profile,
    ]) {
      expect(await start(tester, id), TourStart.started, reason: id.name);
      await pumpTour(tester);
      service.skip();
      await tester.pump();
    }
    expect(
      logs.where((l) => l.contains('tooSoon') || l.contains('limit')),
      isEmpty,
    );
  });

  testWidgets('busy retries and starts when the running tour ends', (
    tester,
  ) async {
    useTallScreen(tester);
    await tester.pumpWidget(TourHarness(keys: keys));
    await finishChatList(tester);
    expect(await start(tester, TourId.chat), TourStart.started);
    await pumpTour(tester);
    final context = tester.element(find.byKey(keys[0]));
    var calls = 0;
    final trigger = TourTrigger(
      canTry: () => true,
      start: () {
        calls++;
        return service.start(
          TourId.inbox,
          steps(),
          context: context,
          after: TourId.chatList,
        );
      },
    );
    addTearDown(trigger.dispose);
    trigger.schedule();
    await tester.pump(const Duration(seconds: 120));
    expect(calls, greaterThan(20));
    expect(trigger.hasStarted, isFalse);
    service.skip();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(trigger.hasStarted, isTrue);
    expect(service.activeId, TourId.inbox);
    await pumpTour(tester);
    service.cancel();
    await tester.pump();
  });

  testWidgets('a busy retry stops when the screen is left', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(TourHarness(keys: keys));
    await finishChatList(tester);
    expect(await start(tester, TourId.chat), TourStart.started);
    await pumpTour(tester);
    final context = tester.element(find.byKey(keys[0]));
    var calls = 0;
    final trigger = TourTrigger(
      canTry: () => true,
      start: () {
        calls++;
        return service.start(
          TourId.inbox,
          steps(),
          context: context,
          after: TourId.chatList,
        );
      },
    );
    addTearDown(trigger.dispose);
    trigger.schedule();
    await tester.pump(const Duration(seconds: 10));
    expect(calls, greaterThan(1));
    trigger.cancel();
    final before = calls;
    service.skip();
    await tester.pump(const Duration(seconds: 10));
    expect(calls, before);
    expect(service.isActive.value, isFalse);
  });

  testWidgets('after: is reported with the rule', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(TourHarness(keys: keys));
    expect(await start(tester, TourId.chat), TourStart.notReady);
    expect(
      logs.last,
      contains('tour:chat start -> notReady:after:chatList not seen'),
    );
  });
}
