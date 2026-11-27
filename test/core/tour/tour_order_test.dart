import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tour_test_support.dart';

void main() {
  late List<GlobalKey> keys;
  late TourService service;
  late DateTime clock;

  List<TourStep> steps() => [
    for (var i = 0; i < 3; i++)
      TourStep(target: keys[i], icon: Icons.star, title: 'T$i', body: 'B$i'),
  ];

  setUp(() {
    keys = List.generate(3, (_) => GlobalKey());
    clock = DateTime(2026, 11, 26, 9);
    service = TourService(
      userId: () => 'u1',
      store: memoryStore(),
      now: () => clock,
    );
  });

  Future<TourStart> start(WidgetTester tester, TourId id, {TourId? after}) =>
      service.start(
        id,
        steps(),
        context: tester.element(find.byKey(keys[0])),
        after: after,
      );

  testWidgets('chat and workspace wait for chatList; nothing is marked', (
    tester,
  ) async {
    await tester.pumpWidget(TourHarness(keys: keys));
    for (final id in [TourId.chat, TourId.workspace]) {
      expect(
        await start(tester, id, after: TourId.chatList),
        TourStart.notReady,
        reason: id.name,
      );
      expect(service.isActive.value, isFalse);
      expect(await service.isSeen(id), isFalse);
    }
  });

  testWidgets('a chatList that was only cancelled does not unlock them', (
    tester,
  ) async {
    await tester.pumpWidget(TourHarness(keys: keys));
    expect(await start(tester, TourId.chatList), TourStart.started);
    await pumpTour(tester);
    service.cancel();
    await tester.pump();
    expect(
      await start(tester, TourId.chat, after: TourId.chatList),
      TourStart.notReady,
    );
  });

  testWidgets('once chatList is skipped they start, one at a time', (
    tester,
  ) async {
    await tester.pumpWidget(TourHarness(keys: keys));
    expect(await start(tester, TourId.chatList), TourStart.started);
    await pumpTour(tester);
    service.skip();
    await tester.pump();
    expect(await service.isSeen(TourId.chatList), isTrue);
    clock = clock.add(const Duration(minutes: 2));

    final first = start(tester, TourId.chat, after: TourId.chatList);
    final second = await start(
      tester,
      TourId.workspace,
      after: TourId.chatList,
    );
    expect(await first, TourStart.started);
    expect(second, TourStart.busy);
    expect(service.activeId, TourId.chat);
    await pumpTour(tester);
    service.cancel();
    await tester.pump();
  });

  testWidgets('another tour on screen means busy, even for chatList', (
    tester,
  ) async {
    await tester.pumpWidget(TourHarness(keys: keys));
    await service.markSeen(TourId.chatList);
    expect(
      await start(tester, TourId.chat, after: TourId.chatList),
      TourStart.started,
    );
    await pumpTour(tester);
    expect(await start(tester, TourId.commands), TourStart.busy);
    service.cancel();
    await tester.pump();
  });

  testWidgets('the commands tour is not held back by chatList', (tester) async {
    await tester.pumpWidget(TourHarness(keys: keys));
    expect(await start(tester, TourId.commands), TourStart.started);
    await pumpTour(tester);
    service.cancel();
    await tester.pump();
  });

  test('every tour is reset by Replay all tours', () async {
    for (final id in TourId.values) {
      await service.markSeen(id);
    }
    await service.resetAll();
    for (final id in TourId.values) {
      expect(await service.isSeen(id), isFalse, reason: id.name);
    }
  });
}
