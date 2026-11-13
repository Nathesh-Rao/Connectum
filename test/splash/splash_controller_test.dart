import 'dart:async';

import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/core/theme/app_spacing.dart';
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

const _step = Duration(milliseconds: 50);

class _Run {
  _Run(this.tester, this.controller);

  final WidgetTester tester;
  final SplashController controller;
  final routes = <String>[];
  int elapsedMs = 0;
  int? startedAt, stoppingAt, idleAt, navigatedAt;
  var _wasStopping = false;

  Future<void> pumpTo(int ms) async {
    while (elapsedMs < ms) {
      await tester.pump(_step);
      elapsedMs += _step.inMilliseconds;
      final s = controller.loader.state;
      if (startedAt == null && s != LogoLoaderState.idle) startedAt = elapsedMs;
      if (s == LogoLoaderState.stopping) {
        stoppingAt ??= elapsedMs;
        _wasStopping = true;
      }
      if (_wasStopping && idleAt == null && s == LogoLoaderState.idle) {
        idleAt = elapsedMs;
      }
      if (routes.isNotEmpty) navigatedAt ??= elapsedMs;
    }
  }
}

Future<_Run> _launch(
  WidgetTester tester, {
  Future<String> Function()? work,
  bool isReduced = false,
}) async {
  late final _Run run;
  final controller = Get.put(
    SplashController(
      session: _FakeSession(),
      store: _FakeStore(),
      deepLinks: _FakeLinks(),
      resolveRoute: work ?? () async => '/done',
      navigate: (r) => run.routes.add(r),
      shouldReduceMotion: () => isReduced,
      usesLogoIntro: false,
    ),
  );
  run = _Run(tester, controller);
  await tester.pumpWidget(
    MaterialApp(home: LogoLoader(controller: controller.loader)),
  );
  return run;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  Get.reset();
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  tearDown(Get.reset);

  testWidgets('starts at 400 ms, stops 2 s after start when work is instant', (
    tester,
  ) async {
    final run = await _launch(tester);
    await run.pumpTo(350);
    expect(run.controller.loader.state, LogoLoaderState.idle);
    await run.pumpTo(500);
    expect(run.startedAt, inInclusiveRange(400, 500));
    await run.pumpTo(2300);
    expect(run.stoppingAt, isNull);
    await run.pumpTo(2500);
    expect(run.stoppingAt, inInclusiveRange(2400, 2500));
    await run.pumpTo(8000);
    expect(run.routes, ['/done']);
    expect(run.navigatedAt! - run.idleAt!, inInclusiveRange(300, 350));
    await _unmount(tester);
  });

  testWidgets(
    'work finishing at 1500 ms stops 2 s later, navigates 300 ms after idle',
    (tester) async {
      final run = await _launch(
        tester,
        work: () async {
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          return '/late';
        },
      );
      await run.pumpTo(3400);
      expect(run.stoppingAt, isNull);
      await run.pumpTo(3600);
      expect(run.stoppingAt, inInclusiveRange(3500, 3600));
      await run.pumpTo(9000);
      expect(run.routes, ['/late']);
      expect(run.navigatedAt! - run.idleAt!, inInclusiveRange(300, 350));
      await _unmount(tester);
    },
  );

  testWidgets('slow work keeps the animation running', (tester) async {
    final done = Completer<String>();
    final run = await _launch(tester, work: () => done.future);
    await run.pumpTo(12000);
    expect(run.controller.loader.state, isNot(LogoLoaderState.idle));
    expect(run.controller.loader.state, isNot(LogoLoaderState.stopping));
    expect(run.routes, isEmpty);
    done.complete('/slow');
    await run.pumpTo(12200);
    expect(run.stoppingAt, isNull);
    await run.pumpTo(14300);
    expect(run.stoppingAt, isNotNull);
    await run.pumpTo(20000);
    expect(run.routes, ['/slow']);
    await _unmount(tester);
  });

  testWidgets('an error in the work still goes through the fallback', (
    tester,
  ) async {
    final run = await _launch(
      tester,
      work: () async => throw StateError('boom'),
    );
    await run.pumpTo(8000);
    expect(run.routes, hasLength(1));
    expect(run.controller.loader.isIdle, isTrue);
    await _unmount(tester);
  });

  testWidgets('a second trigger navigates once', (tester) async {
    final run = await _launch(tester);
    await run.pumpTo(100);
    unawaited(run.controller.run());
    unawaited(run.controller.run());
    await run.pumpTo(9000);
    expect(run.routes, hasLength(1));
    await _unmount(tester);
  });

  testWidgets('dispose mid-sequence cancels everything', (tester) async {
    final run = await _launch(tester);
    await run.pumpTo(1000);
    await tester.pumpWidget(const SizedBox());
    Get.delete<SplashController>();
    await tester.pump(const Duration(seconds: 10));
    expect(run.routes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose while stopping does not navigate or throw', (
    tester,
  ) async {
    final run = await _launch(tester);
    await run.pumpTo(2700);
    expect(run.controller.loader.state, LogoLoaderState.stopping);
    await tester.pumpWidget(const SizedBox());
    Get.delete<SplashController>();
    await tester.pump(const Duration(seconds: 10));
    expect(run.routes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion skips the animation and navigates after 300 ms', (
    tester,
  ) async {
    final run = await _launch(tester, isReduced: true);
    await run.pumpTo(250);
    expect(run.routes, isEmpty);
    await run.pumpTo(400);
    expect(run.routes, ['/done']);
    expect(run.startedAt, isNull);
    await _unmount(tester);
  });

  testWidgets(
    'a new controller runs the sequence again (second splash entry)',
    (tester) async {
      var run = await _launch(tester);
      await run.pumpTo(9000);
      expect(run.routes, hasLength(1));
      await _unmount(tester);
      run = await _launch(tester);
      await run.pumpTo(9000);
      expect(run.routes, hasLength(1));
      expect(run.startedAt, isNotNull);
      await _unmount(tester);
    },
  );

  testWidgets('the splash view shows the LogoLoader at the splash size, idle', (
    tester,
  ) async {
    final controller = Get.put(
      SplashController(
        session: _FakeSession(),
        store: _FakeStore(),
        deepLinks: _FakeLinks(),
        resolveRoute: () async => '/done',
        navigate: (_) {},
        shouldReduceMotion: () => false,
        usesLogoIntro: false,
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SplashView()));
    await tester.pump(const Duration(milliseconds: 100));
    final size = tester.getSize(find.byType(LogoLoader));
    expect(
      size,
      const Size(AppSpacing.splashLogoSize, AppSpacing.splashLogoSize),
    );
    expect(controller.loader.state, LogoLoaderState.idle);
    await _unmount(tester);
  });
}
