import 'dart:io';

import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/routes/invite_service.dart';
import 'package:connectum/core/widgets/onboarding_art/onboarding_art.dart';
import 'package:connectum/core/widgets/onboarding_art_stage.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/features/onboarding/onboarding_binding.dart';
import 'package:connectum/features/onboarding/onboarding_controller.dart';
import 'package:connectum/features/onboarding/onboarding_view.dart';
import 'package:connectum/features/splash/splash_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _SpyStore implements SessionStore {
  final writes = <String, String>{};

  @override
  Future<void> writeValue(String key, String value) async =>
      writes[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeInvite implements InviteService {
  @override
  void attach() {}
  @override
  void detach() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// The real controller, with the invite sheet replaced by a counter.
class _Spied extends OnboardingController {
  _Spied(SessionStore store, InviteService invite)
    : super(store: store, isReplay: false, invite: invite);
  int inviteOpens = 0;

  @override
  void openInviteSheet() => inviteOpens++;
}

Future<void> _loadFonts() async {
  for (final (family, weights) in [
    ('PlusJakartaSans', ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']),
    ('SpaceGrotesk', ['SemiBold', 'Bold']),
  ]) {
    final loader = FontLoader(family);
    for (final w in weights) {
      final bytes = File('assets/fonts/$family-$w.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

const _step = Duration(milliseconds: 100);

Future<void> _settle(WidgetTester t, [int steps = 8]) async {
  for (var i = 0; i < steps; i++) {
    await t.pump(_step);
  }
}

Iterable<OnboardingArtState> _states(WidgetTester t) =>
    t.stateList<OnboardingArtState>(find.byType(OnboardingArt));

Set<OnboardingArtKind> _kinds(WidgetTester t) => {
  for (final w in t.widgetList<OnboardingArt>(find.byType(OnboardingArt)))
    w.kind,
};

void main() {
  setUpAll(_loadFonts);

  late _SpyStore store;
  late _Spied controller;
  final errors = <String>[];

  setUp(() {
    Get.testMode = true;
    store = _SpyStore();
    controller = _Spied(store, _FakeInvite());
    errors.clear();
  });
  tearDown(Get.reset);

  /// The real onboarding on the real route and binding's shape (the controller
  /// is the spied subclass), with a stand-in login page.
  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(411, 900),
    bool reducedMotion = false,
  }) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (d) =>
        errors.add(d.exceptionAsString().split('\n').first);
    addTearDown(() => FlutterError.onError = previous);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Get.put<SessionStore>(store);
    Get.put<InviteService>(_FakeInvite());
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: AppRoutes.onboarding,
        builder: reducedMotion
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              )
            : null,
        getPages: [
          GetPage(
            name: AppRoutes.onboarding,
            page: () => const OnboardingView(),
            binding: BindingsBuilder(
              () => Get.put<OnboardingController>(controller),
            ),
          ),
          GetPage(
            name: AppRoutes.authentication,
            page: () => const Text('LOGIN'),
          ),
        ],
      ),
    );
    await _settle(tester);
  }

  testWidgets('the binding still builds the controller from the store', (
    tester,
  ) async {
    Get.put<SessionStore>(store);
    Get.put<InviteService>(_FakeInvite());
    OnboardingBinding().dependencies();
    expect(Get.find<OnboardingController>(), isNotNull);
  });

  testWidgets('swiping shows network, buildings, shield and the copy follows', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(_kinds(tester), {OnboardingArtKind.network});
    expect(find.text('All your conversations in one place'), findsOneWidget);
    expect(find.text('01 / 03'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Back'), findsNothing);

    await tester.drag(find.byType(OnboardingArt).first, const Offset(-300, 0));
    await _settle(tester, 12);
    expect(controller.page.value, 1);
    expect(_kinds(tester), {OnboardingArtKind.buildings});
    expect(find.text('Work across multiple enterprises'), findsOneWidget);
    expect(find.text('02 / 03'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await tester.drag(find.byType(OnboardingArt).first, const Offset(-300, 0));
    await _settle(tester, 12);
    expect(controller.page.value, 2);
    expect(_kinds(tester), {OnboardingArtKind.shield});
    expect(find.text('Secure, simple and ready to go'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await _settle(tester, 12);
    expect(controller.page.value, 1);
    expect(errors, isEmpty);
  });

  testWidgets('Continue steps through the pages and the dots jump', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Continue'));
    await _settle(tester, 12);
    expect(controller.page.value, 1);
    await tester.tap(find.text('Continue'));
    await _settle(tester, 12);
    expect(controller.page.value, 2);
    expect(store.writes, isEmpty);
  });

  testWidgets('Get Started writes the completed flag and opens login', (
    tester,
  ) async {
    await pumpApp(tester);
    controller.goTo(2);
    await _settle(tester, 12);
    await tester.tap(find.text('Get Started'));
    await _settle(tester, 14);
    expect(store.writes, {SplashController.onboardingSeenKey: 'true'});
    expect(find.text('LOGIN'), findsOneWidget);
  });

  testWidgets('Skip writes the flag and opens login', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Skip'));
    await _settle(tester, 14);
    expect(store.writes, {SplashController.onboardingSeenKey: 'true'});
    expect(find.text('LOGIN'), findsOneWidget);
  });

  testWidgets('the invite row opens the invite sheet and nothing else', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Have an invite code or link?'));
    await tester.pump(_step);
    expect(controller.inviteOpens, 1);
    expect(store.writes, isEmpty);
    expect(find.text('LOGIN'), findsNothing);
  });

  for (final width in [320.0, 360.0, 411.0, 800.0]) {
    testWidgets('the art slot is full width at ${width.toInt()} dp', (
      tester,
    ) async {
      await pumpApp(tester, size: Size(width, width < 700 ? 900 : 1280));
      final stage = tester.getRect(find.byType(OnboardingArtStage));
      expect(stage.left, closeTo(0, 0.01));
      expect(stage.right, closeTo(width, 0.01));
      final page = tester.getRect(find.byType(PageView).first);
      expect(page.left, closeTo(0, 0.01));
      expect(page.right, closeTo(width, 0.01));
      final art = tester.getRect(find.byType(OnboardingArt).first);
      expect(
        art.width,
        closeTo(width < 700 ? width : OnboardingArtStage.maxArtWidth, 0.01),
      );
      expect(art.center.dx, closeTo(width / 2, 0.01));
    });
  }

  // 320x568: the fixed copy box, buttons and gaps already overflow by 34 dp
  // (text, measured before this change); the art slot must not add to it.
  for (final (size, allowed) in [
    (const Size(320, 568), 34.0),
    (const Size(360, 640), 0.0),
  ]) {
    testWidgets('overflow at ${size.width.toInt()}x${size.height.toInt()}: '
        'at most $allowed, the art slot itself fits', (tester) async {
      await pumpApp(tester, size: size);
      final overflow = RegExp(r'overflowed by ([\d.]+) pixels');
      for (final e in errors) {
        final m = overflow.firstMatch(e);
        expect(m, isNotNull, reason: 'unexpected error: $e');
        expect(double.parse(m![1]!), lessThanOrEqualTo(allowed + 0.5));
      }
      final slot = tester.getRect(find.byType(OnboardingArtStage));
      final art = tester.getRect(find.byType(OnboardingArt).first);
      expect(slot.height, greaterThan(0));
      expect(art.left, greaterThanOrEqualTo(slot.left - 0.01));
      expect(art.right, lessThanOrEqualTo(slot.right + 0.01));
      expect(art.top, greaterThanOrEqualTo(slot.top - 0.01));
      expect(art.bottom, lessThanOrEqualTo(slot.bottom + 0.01));
    });
  }

  testWidgets('only the active page animates; the others are muted', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(_states(tester), hasLength(1));
    expect(_states(tester).single.isTicking, isTrue);

    // mid-swipe two pages are mounted: the one leaving is already muted
    final g = await tester.startGesture(
      tester.getCenter(find.byType(OnboardingArt).first),
    );
    await g.moveBy(const Offset(-120, 0));
    await tester.pump(_step);
    await g.moveBy(const Offset(-120, 0));
    await tester.pump(_step);
    await g.up();
    await tester.pump(_step);
    for (final s in _states(tester)) {
      expect(
        s.isTicking,
        s.widget.isActive,
        reason: '${s.widget.kind.name} ticks only while active',
      );
    }
    await _settle(tester, 14);
    expect(controller.page.value, 1);
    expect(_states(tester), hasLength(1));
    expect(_states(tester).single.widget.kind, OnboardingArtKind.buildings);
    expect(_states(tester).single.isTicking, isTrue);
  });

  testWidgets('app pause mutes the ticker and resume restarts it', (
    tester,
  ) async {
    await pumpApp(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(_step);
    for (final s in _states(tester)) {
      expect(s.isTicking, isFalse);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(_step);
    expect(_states(tester).single.isTicking, isTrue);
  });

  testWidgets('a covered route mutes the ticker', (tester) async {
    await pumpApp(tester);
    Get.toNamed<void>(AppRoutes.authentication);
    await _settle(tester, 12);
    for (final s in _states(tester)) {
      expect(s.isTicking, isFalse);
    }
    Get.back<void>();
    await _settle(tester, 12);
    expect(_states(tester).single.isTicking, isTrue);
  });

  testWidgets('reduced motion shows the static frame and creates no ticker', (
    tester,
  ) async {
    await pumpApp(tester, reducedMotion: true);
    expect(_states(tester), isNotEmpty);
    for (final s in _states(tester)) {
      expect(s.isTicking, isFalse);
    }
    controller.goTo(2);
    await _settle(tester, 12);
    for (final s in _states(tester)) {
      expect(s.isTicking, isFalse);
    }
    expect(_kinds(tester), {OnboardingArtKind.shield});
  });

  test(
    'the onboarding has no demo-only branch, so DEMO_MODE shows the same one',
    () {
      for (final f in Directory('lib/features/onboarding').listSync()) {
        if (f is File) {
          expect(
            f.readAsStringSync().contains('DemoMode'),
            isFalse,
            reason: f.path,
          );
        }
      }
    },
  );
}
