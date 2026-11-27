import 'package:connectum/core/tour/tour_demo.dart';
import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_step.dart';
import 'package:connectum/core/tour/tour_store.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:connectum/core/tour/widgets/tour_intro_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tour_test_support.dart';

void main() {
  late List<GlobalKey> keys;
  late Map<String, String> data;
  final introKey = TourStore.introKeyOf('u1');
  var hasSample = false;
  var isRealData = false;

  TourDemo demo() => TourDemo(
    seed: () {
      if (isRealData) return false;
      hasSample = true;
      return true;
    },
    restore: () => hasSample = false,
  );

  List<TourStep> steps() => [
    for (var i = 0; i < 3; i++)
      TourStep(target: keys[i], icon: Icons.info, title: 'T$i', body: 'b$i'),
  ];

  TourService newService() =>
      TourService(userId: () => 'u1', store: memoryStore(data, true));

  setUp(() {
    keys = [GlobalKey(), GlobalKey(), GlobalKey()];
    data = {};
    hasSample = false;
    isRealData = false;
  });

  Future<(Future<TourStart>, BuildContext)> begin(
    WidgetTester tester,
    TourService service, {
    bool withDemo = true,
  }) async {
    useTallScreen(tester);
    await tester.pumpWidget(TourHarness(keys: keys));
    final context = tester.element(find.byKey(keys[0]));
    final result = service.start(
      TourId.chatList,
      steps(),
      context: context,
      demo: withDemo ? demo() : null,
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return (result, context);
  }

  testWidgets('shows once, is persisted, and Show me around starts the tour', (
    tester,
  ) async {
    final service = newService();
    final (result, _) = await begin(tester, service);
    expect(find.text(TourTexts.introTitle), findsOneWidget);
    expect(find.text(TourTexts.introBody), findsOneWidget);
    await tester.tap(find.text(TourTexts.introStart));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(await result, TourStart.started);
    expect(data[introKey], '1');
    expect(find.text(TourTexts.introTitle), findsNothing);
    expect(find.text('T0'), findsOneWidget);
    service.skip();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('not shown again after a restart', (tester) async {
    data[introKey] = '1';
    final service = newService();
    final (result, _) = await begin(tester, service);
    expect(find.text(TourTexts.introTitle), findsNothing);
    expect(await result, TourStart.started);
    service.skip();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('real data or no sample: the dialog still comes first', (
    tester,
  ) async {
    isRealData = true;
    final service = newService();
    final (result, _) = await begin(tester, service, withDemo: false);
    expect(find.text(TourTexts.introTitle), findsOneWidget);
    expect(find.text('T0'), findsNothing);
    await tester.tap(find.text(TourTexts.introStart));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(await result, TourStart.started);
    expect(data[introKey], '1');
    expect(find.text('T0'), findsOneWidget);
    service.skip();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a second tour does not show it again', (tester) async {
    isRealData = true;
    final service = newService();
    final (result, context) = await begin(tester, service);
    await tester.tap(find.text(TourTexts.introStart));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(await result, TourStart.started);
    service.skip();
    await tester.pump(const Duration(milliseconds: 100));
    final second = service.start(
      TourId.values.firstWhere((t) => t != TourId.chatList),
      steps(),
      context: context,
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(TourTexts.introTitle), findsNothing);
    expect(await second, TourStart.started);
    service.skip();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('Skip tours marks every tour seen and puts the sample back', (
    tester,
  ) async {
    final service = newService();
    final (result, _) = await begin(tester, service);
    await tester.tap(find.text(TourTexts.introSkip));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(await result, TourStart.seen);
    expect(data[introKey], '1');
    for (final id in TourId.values) {
      expect(data[TourStore.keyOf('u1', id)], '1');
    }
    expect(hasSample, isFalse);
  });

  testWidgets('Replay all tours brings the intro back once per round', (
    tester,
  ) async {
    data[introKey] = '1';
    final service = newService();
    await service.resetAll();
    expect(data.containsKey(introKey), isFalse);
    isRealData = true;
    final (result, context) = await begin(tester, service);
    expect(find.text(TourTexts.introTitle), findsOneWidget);
    await tester.tap(find.text(TourTexts.introStart));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(await result, TourStart.started);
    service.skip();
    await tester.pump(const Duration(milliseconds: 100));
    final second = service.start(
      TourId.values.firstWhere((t) => t != TourId.chatList),
      steps(),
      context: context,
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(TourTexts.introTitle), findsNothing);
    expect(await second, TourStart.started);
    service.skip();
    await tester.pump(const Duration(milliseconds: 100));
  });

  test('the intro flag is per user', () async {
    final a = TourService(userId: () => 'u1', store: memoryStore(data, true));
    final b = TourService(userId: () => 'u2', store: memoryStore(data, true));
    data[TourStore.introKeyOf('u1')] = '1';
    expect(TourStore.introKeyOf('u1'), isNot(TourStore.introKeyOf('u2')));
    expect(await memoryStore(data, true).isIntroSeen('u2'), isFalse);
    await b.resetAll();
    expect(data[TourStore.introKeyOf('u1')], '1', reason: 'u1 is untouched');
    await a.resetAll();
    expect(data.containsKey(TourStore.introKeyOf('u1')), isFalse);
  });

  testWidgets('tap outside and back keep the dialog', (tester) async {
    final service = newService();
    final (result, _) = await begin(tester, service);
    await tester.tapAt(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(TourTexts.introTitle), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(TourTexts.introTitle), findsOneWidget);
    expect(data.containsKey(introKey), isFalse);
    await tester.tap(find.text(TourTexts.introStart));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(await result, TourStart.started);
    service.skip();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('both buttons have semantics labels', (tester) async {
    final handle = tester.ensureSemantics();
    final service = newService();
    final (result, _) = await begin(tester, service);
    expect(find.bySemanticsLabel(TourTexts.introStartLabel), findsOneWidget);
    expect(find.bySemanticsLabel(TourTexts.introSkipLabel), findsOneWidget);
    await tester.tap(find.text(TourTexts.introStart));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await result;
    service.skip();
    await tester.pump(const Duration(milliseconds: 100));
    handle.dispose();
  });

  for (final reduced in [true, false]) {
    testWidgets('fits 320 px at 1.5x text (reduce motion: $reduced)', (
      tester,
    ) async {
      await loadAppFont();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              textScaler: const TextScaler.linear(1.5),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => TourIntroDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(Dialog));
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(320));
      expect(find.text(TourTexts.introStart), findsOneWidget);
      expect(find.text(TourTexts.introSkip), findsOneWidget);
      final screen = const Rect.fromLTWH(0, 0, 320, 640);
      expect(
        screen.contains(tester.getCenter(find.text(TourTexts.introStart))),
        isTrue,
      );
      expect(
        screen.contains(tester.getCenter(find.text(TourTexts.introSkip))),
        isTrue,
      );
    });
  }
}
