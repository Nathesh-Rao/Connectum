import 'dart:async';

import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/core/widgets/logo_intro/logo_intro.dart';
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

Future<List<String>> _launch(
  WidgetTester tester, {
  Future<String> Function()? work,
  bool isReduced = false,
}) async {
  final routes = <String>[];
  Get.put(
    SplashController(
      session: _FakeSession(),
      store: _FakeStore(),
      deepLinks: _FakeLinks(),
      resolveRoute: work ?? () async => '/done',
      navigate: routes.add,
      usesLogoIntro: true,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: isReduced),
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
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  tearDown(Get.reset);

  testWidgets('shows the LogoIntro, no spinner or loader', (tester) async {
    await _launch(tester);
    expect(find.byType(LogoIntro), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getSize(find.byType(LogoIntro)).width, kSplashLogoIntroWidth);
    await _unmount(tester);
  });

  testWidgets('navigates only after the animation ends plus the hold', (
    tester,
  ) async {
    final routes = await _launch(tester);
    await _pump(tester, 3300);
    expect(routes, isEmpty);
    await _pump(tester, 400); // 3700: hold (500 ms) not over
    expect(routes, isEmpty);
    await _pump(tester, 300); // 4000
    expect(routes, ['/done']);
    await _unmount(tester);
  });

  testWidgets('slow work keeps the final frame and navigates when ready', (
    tester,
  ) async {
    final done = Completer<String>();
    final routes = await _launch(tester, work: () => done.future);
    await _pump(tester, 8000);
    expect(routes, isEmpty);
    expect(find.byType(LogoIntro), findsOneWidget);
    done.complete('/slow');
    await _pump(tester, 100);
    expect(routes, ['/slow']);
    await _unmount(tester);
  });

  testWidgets('reduced motion: final frame, navigates after the hold', (
    tester,
  ) async {
    final routes = await _launch(tester, isReduced: true);
    await _pump(tester, 400);
    expect(routes, isEmpty);
    await _pump(tester, 250);
    expect(routes, ['/done']);
    await _unmount(tester);
  });

  testWidgets('the flag keeps the old flow available', (tester) async {
    expect(kSplashUsesLogoIntro, isTrue);
    // The old flow itself is covered by splash_controller_test.dart
    // (usesLogoIntro: false).
  });
}
