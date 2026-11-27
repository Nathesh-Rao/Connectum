import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/tour_step.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:connectum/core/tour/widgets/tour_card.dart';
import 'package:connectum/core/tour/widgets/tour_card_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tour_test_support.dart';

enum _Spot { top, bottom, tall, drawer }

void main() {
  const barHeight = 64.0;
  const screen = Size(320, 640);
  const statusBar = 24.0;

  group('TourPlacement', () {
    const free = Rect.fromLTRB(0, 24, 320, 576);
    const card = Size(296, 200);

    test('goes below the target when there is room', () {
      final at = TourPlacement.place(
        free: free,
        spot: const Rect.fromLTWH(20, 60, 100, 40),
        card: card,
        side: TourSide.auto,
      );
      expect(at.dy, 60 + 40 + TourPlacement.gap);
    });

    test('goes above a target near the bottom', () {
      final at = TourPlacement.place(
        free: free,
        spot: const Rect.fromLTWH(20, 500, 100, 40),
        card: card,
        side: TourSide.below,
      );
      expect(at.dy + card.height, 500 - TourPlacement.gap);
    });

    test('docks above the bottom edge for a tall target', () {
      final at = TourPlacement.place(
        free: free,
        spot: const Rect.fromLTWH(0, 24, 250, 552),
        card: card,
        side: TourSide.below,
      );
      expect(at.dy + card.height, free.bottom - TourPlacement.margin);
    });
  });

  group('the card on screen', () {
    late TourService service;
    late GlobalKey target;
    late GlobalKey barKey;
    late GlobalKey<ScaffoldState> scaffold;
    late int taps;

    Future<void> boot(WidgetTester tester, _Spot spot) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      service = TourService(userId: () => 'u1', store: memoryStore());
      target = GlobalKey();
      barKey = GlobalKey();
      scaffold = GlobalKey<ScaffoldState>();
      service.bottomBarKey = barKey;
      taps = 0;
      final second = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(1.5),
              padding: const EdgeInsets.only(top: statusBar),
            ),
            child: child!,
          ),
          home: Scaffold(
            key: scaffold,
            drawer: Drawer(
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  key: spot == _Spot.drawer ? target : null,
                  width: 200,
                  height: 120,
                ),
              ),
            ),
            body: Stack(
              children: [
                if (spot == _Spot.top)
                  Positioned(
                    top: statusBar,
                    left: 8,
                    right: 8,
                    height: 40,
                    child: SizedBox(key: target),
                  ),
                if (spot == _Spot.bottom)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    height: 40,
                    child: SizedBox(key: target),
                  ),
                if (spot == _Spot.tall)
                  Positioned.fill(child: SizedBox(key: target)),
                Positioned(
                  top: 100,
                  left: 8,
                  child: TextButton(
                    onPressed: () => taps++,
                    child: const Text('Under'),
                  ),
                ),
                Positioned(
                  top: 300,
                  left: 8,
                  child: SizedBox(key: second, width: 80, height: 40),
                ),
              ],
            ),
            bottomNavigationBar: SizedBox(key: barKey, height: barHeight),
          ),
        ),
      );
      if (spot == _Spot.drawer) {
        scaffold.currentState!.openDrawer();
        await tester.pumpAndSettle();
        tester.element(find.byType(Drawer));
      }
      final context = tester.element(find.byType(Scaffold));
      final steps = [
        TourStep(
          target: target,
          icon: Icons.star,
          title: 'First step',
          body: 'This is the first thing, with a few words.',
        ),
        TourStep(
          target: second,
          icon: Icons.star,
          title: 'Second step',
          body: 'And then the next.',
          actions: [],
        ),
      ];
      expect(
        await service.start(
          TourId.chatList,
          steps,
          context: spot == _Spot.drawer
              ? tester.element(find.byType(Drawer))
              : context,
        ),
        TourStart.started,
      );
      await pumpTour(tester);
    }

    void expectOnScreen(WidgetTester tester, {bool isLast = false}) {
      final free = TourPlacement.freeArea(
        screen: screen,
        insets: const EdgeInsets.only(top: statusBar),
        barTop: screen.height - barHeight,
      );
      final rect = tester.getRect(find.byType(TourCard));
      expect(rect.left, greaterThanOrEqualTo(free.left));
      expect(rect.right, lessThanOrEqualTo(free.right));
      expect(rect.top, greaterThanOrEqualTo(free.top));
      expect(rect.bottom, lessThanOrEqualTo(free.bottom));
      for (final label in [
        TourTexts.skip,
        isLast ? TourTexts.done : TourTexts.next,
      ]) {
        final r = tester.getRect(find.text(label));
        expect(r.left, greaterThanOrEqualTo(0), reason: label);
        expect(r.top, greaterThanOrEqualTo(0), reason: label);
        expect(r.right, lessThanOrEqualTo(screen.width), reason: label);
        expect(r.bottom, lessThanOrEqualTo(free.bottom), reason: label);
      }
    }

    for (final spot in _Spot.values) {
      testWidgets('is on screen and Next works: ${spot.name}', (tester) async {
        await boot(tester, spot);
        expect(tester.takeException(), isNull);
        expectOnScreen(tester);
        await tester.tap(find.text(TourTexts.next));
        await pumpTour(tester);
        expect(find.text('Second step'), findsOneWidget);
        expectOnScreen(tester, isLast: true);
        expect(tester.takeException(), isNull);
        service.cancel();
      });

      testWidgets('Skip ends the tour: ${spot.name}', (tester) async {
        await boot(tester, spot);
        await tester.tap(find.text(TourTexts.skip));
        await pumpTour(tester);
        expect(service.isActive.value, isFalse);
        expect(await service.isSeen(TourId.chatList), isTrue);
      });
    }

    testWidgets('the scrim keeps taps off the screen underneath', (
      tester,
    ) async {
      await boot(tester, _Spot.top);
      await tester.tapAt(tester.getCenter(find.text('Under')));
      await tester.pump();
      expect(taps, 0);
      service.cancel();
    });

    testWidgets('sits above an open drawer', (tester) async {
      await boot(tester, _Spot.drawer);
      expect(scaffold.currentState!.isDrawerOpen, isTrue);
      final skip = find.text(TourTexts.skip);
      await tester.tap(skip);
      await pumpTour(tester);
      expect(service.isActive.value, isFalse);
    });
  });
}
