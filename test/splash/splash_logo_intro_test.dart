import 'dart:async';

import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/core/widgets/logo_intro/logo_intro.dart';
import 'package:connectum/core/widgets/logo_loader/logo_loader.dart';
import 'package:connectum/data/repositories/session_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/features/splash/splash_controller.dart';
import 'package:connectum/features/splash/splash_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _FakeSession implements SessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeStore implements SessionStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeLinks implements DeepLinkService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

// Real time at which the intro reports "finished", then the hold.
final _finishMs = (kSplashFinishAt / kSplashIntroSpeed * 1000).round();
final _holdMs = kSplashHold.inMilliseconds;

Future<List<String>> _launch(
  WidgetTester tester, {
  Future<String> Function()? work,
  bool isReduced = false,
  bool usesLogoIntro = true,
}) async {
  final routes = <String>[];
  Get.put(
    SplashController(
      session: _FakeSession(),
      store: _FakeStore(),
      deepLinks: _FakeLinks(),
      resolveRoute: work ?? () async => '/done',
      navigate: routes.add,
      shouldReduceMotion: () => isReduced,
      usesLogoIntro: usesLogoIntro,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 780),
          disableAnimations: isReduced,
        ),
        child: const SplashView(),
      ),
    ),
  );
  return routes;
}

Future<void> _pump(WidgetTester tester, int ms) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  Get.reset();
  await tester.pump(const Duration(seconds: 8));
}

void main() {
  tearDown(Get.reset);

  testWidgets('shows the LogoIntro, no spinner or loader', (tester) async {
    await _launch(tester);
    expect(find.byType(LogoIntro), findsOneWidget);
    expect(find.byType(LogoLoader), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getSize(find.byType(LogoIntro)).width, kSplashLogoSize);
    await _unmount(tester);
  });

  testWidgets('no navigation before finishAt / speed + hold, then it goes', (
    tester,
  ) async {
    final routes = await _launch(tester);
    await tester.pump();
    await _pump(tester, _finishMs - 200);
    expect(routes, isEmpty);
    await _pump(tester, 250); // just past finishAt: hold running
    expect(routes, isEmpty);
    await _pump(tester, _holdMs - 100);
    expect(routes, isEmpty);
    await _pump(tester, 250);
    expect(routes, ['/done']);
    await _unmount(tester);
  });

  testWidgets('slow work keeps the final frame and navigates when ready', (
    tester,
  ) async {
    final done = Completer<String>();
    final routes = await _launch(tester, work: () => done.future);
    await _pump(tester, 9000);
    expect(routes, isEmpty);
    expect(find.byType(LogoIntro), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    done.complete('/slow');
    await _pump(tester, 100);
    expect(routes, ['/slow']);
    await _unmount(tester);
  });

  testWidgets('reduced motion: final frame, navigates as soon as ready', (
    tester,
  ) async {
    final routes = await _launch(tester, isReduced: true);
    await tester.pump();
    await tester.pump();
    expect(routes, ['/done']);
    await _unmount(tester);
  });

  testWidgets('reduced motion waits for slow work', (tester) async {
    final done = Completer<String>();
    final routes = await _launch(
      tester,
      isReduced: true,
      work: () => done.future,
    );
    await _pump(tester, 2000);
    expect(routes, isEmpty);
    done.complete('/late');
    await _pump(tester, 100);
    expect(routes, ['/late']);
    await _unmount(tester);
  });

  testWidgets('kSplashUsesLogoIntro false keeps the previous flow', (
    tester,
  ) async {
    final routes = await _launch(tester, usesLogoIntro: false);
    expect(find.byType(LogoIntro), findsNothing);
    expect(find.byType(LogoLoader), findsOneWidget);
    // 400 ms start + 2 s extra + stop + 300 ms: nothing before 2.7 s.
    await _pump(tester, 2600);
    expect(routes, isEmpty);
    await _pump(tester, 3000);
    expect(routes, ['/done']);
    await _unmount(tester);
  });

  test('TUNE defaults', () {
    expect(kSplashUsesLogoIntro, isTrue);
    expect(kSplashIntroSpeed, 1.25);
    expect(kSplashFinishAt, IntroTiming.last + 0.3);
    expect(kSplashHold, const Duration(milliseconds: 400));
  });
}
