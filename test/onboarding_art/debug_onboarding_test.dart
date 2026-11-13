import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/widgets/onboarding_art/onboarding_art.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/features/debug_onboarding/debug_onboarding_binding.dart';
import 'package:connectum/features/debug_onboarding/debug_onboarding_controller.dart';
import 'package:connectum/features/debug_onboarding/debug_onboarding_view.dart';
import 'package:connectum/features/debug_onboarding_anim/debug_onboarding_anim_binding.dart';
import 'package:connectum/features/debug_onboarding_anim/debug_onboarding_anim_controller.dart';
import 'package:connectum/features/debug_onboarding_anim/debug_onboarding_anim_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _SpyStore implements SessionStore {
  final writes = <String>[];

  @override
  Future<void> writeValue(String key, String value) async => writes.add(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _step = Duration(milliseconds: 100);

Future<void> _settle(WidgetTester t, [int steps = 8]) async {
  for (var i = 0; i < steps; i++) {
    await t.pump(_step);
  }
}

Set<OnboardingArtKind> _kinds(WidgetTester t) => {
  for (final w in t.widgetList<OnboardingArt>(find.byType(OnboardingArt)))
    w.kind,
};

void main() {
  late _SpyStore store;

  void ignoreOverflow() {
    // The test font is wider than Space Grotesk, so the fixed-height copy box
    // overflows here (as it does on the main onboarding); only that is ignored.
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  }

  setUp(() {
    Get.testMode = true;
    store = _SpyStore();
    Get.put<SessionStore>(store);
  });
  tearDown(Get.reset);

  Future<void> pumpApp(WidgetTester tester) async {
    ignoreOverflow();
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: '/home',
        getPages: [
          GetPage(
            name: '/home',
            page: () => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Get.toNamed<void>(AppRoutes.debugOnboarding),
                  child: const Text('HOME'),
                ),
              ),
            ),
          ),
          GetPage(
            name: AppRoutes.debugOnboarding,
            page: () => const DebugOnboardingView(),
            binding: DebugOnboardingBinding(),
          ),
          GetPage(
            name: AppRoutes.authentication,
            page: () => const Text('LOGIN'),
          ),
        ],
      ),
    );
    await tester.tap(find.text('HOME'));
    await _settle(tester, 10);
  }

  testWidgets('the three pages show the network, buildings and shield art', (
    tester,
  ) async {
    await pumpApp(tester);
    final c = Get.find<DebugOnboardingController>();
    expect(_kinds(tester), contains(OnboardingArtKind.network));
    expect(find.text('All your conversations in one place'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    c.goTo(1);
    await _settle(tester, 10);
    expect(c.page.value, 1);
    expect(_kinds(tester), contains(OnboardingArtKind.buildings));
    expect(find.text('Work across multiple enterprises'), findsOneWidget);

    c.goTo(2);
    await _settle(tester, 10);
    expect(_kinds(tester), contains(OnboardingArtKind.shield));
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('the pages swipe', (tester) async {
    await pumpApp(tester);
    final c = Get.find<DebugOnboardingController>();
    await tester.drag(find.byType(OnboardingArt).first, const Offset(-300, 0));
    await _settle(tester, 10);
    expect(c.page.value, 1);
  });

  testWidgets('finishing goes back, writes no flag and never opens login', (
    tester,
  ) async {
    await pumpApp(tester);
    final c = Get.find<DebugOnboardingController>();
    c.goTo(2);
    await _settle(tester, 10);
    await tester.tap(find.text('Get Started'));
    await _settle(tester, 12);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('LOGIN'), findsNothing);
    expect(store.writes, isEmpty);
  });

  testWidgets('skip behaves the same', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Skip'));
    await _settle(tester, 12);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('LOGIN'), findsNothing);
    expect(store.writes, isEmpty);
  });

  testWidgets('the lab controls drive all three animations', (tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DebugOnboardingAnimBinding().dependencies();
    final c = Get.find<DebugOnboardingAnimController>();
    await tester.pumpWidget(
      const GetMaterialApp(home: DebugOnboardingAnimView()),
    );
    await _settle(tester, 4);
    expect(find.byType(OnboardingArt), findsNWidgets(3));
    expect(c.clock.time.value, greaterThan(0));

    await tester.tap(find.text('Pause'));
    await tester.pump(_step);
    expect(c.isPlaying.value, isFalse);
    final held = c.clock.time.value;
    await _settle(tester, 3);
    expect(c.clock.time.value, held);

    c.seek(7);
    await tester.pump(_step);
    for (final a in c.art.values) {
      expect(a.time.value, 7);
    }

    await tester.tap(find.text('Replay'));
    await tester.pump(_step);
    expect(c.isPlaying.value, isTrue);
    expect(c.clock.time.value, lessThan(0.5));

    // default: each art plays at its constant, 1.25x; the selector lists the
    // multiples of the HTML speed
    expect(c.speedChoice.value, isNull);
    expect(c.art.values.every((a) => a.speed == 1.25), isTrue);
    for (final label in ['0.5x', '1.0x', '1.25x', '1.5x', '2.0x']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.textContaining('effective: network 1.25x'), findsOneWidget);
    await tester.tap(find.text('0.5x'));
    await tester.pump(_step);
    expect(c.speedChoice.value, 0.5);
    expect(c.art.values.every((a) => a.speed == 0.5), isTrue);
    expect(find.textContaining('effective: network 0.5x'), findsOneWidget);
    await tester.tap(find.text('Default'));
    await tester.pump(_step);
    expect(c.speedChoice.value, isNull);
    expect(c.art.values.every((a) => a.speed == 1.25), isTrue);

    await tester.tap(find.byType(Switch).first);
    await tester.pump(_step);
    expect(c.isBlueOnly.value, isTrue);
    expect(
      tester.widgetList<OnboardingArt>(find.byType(OnboardingArt)).every((w) => w.blueOnly),
      isTrue,
    );

    // tier 2 persons: on by default, the switch takes them off the network
    expect(c.isTier2.value, isTrue);
    OnboardingArt network() => tester
        .widgetList<OnboardingArt>(find.byType(OnboardingArt))
        .firstWhere((w) => w.kind == OnboardingArtKind.network);
    expect(network().networkTier2, isTrue);
    expect(find.text('Tier 2 persons: on (network)'), findsOneWidget);
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump(_step);
    expect(c.isTier2.value, isFalse);
    expect(network().networkTier2, isFalse);
    expect(find.text('Tier 2 persons: off (network)'), findsOneWidget);
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump(_step);
    expect(c.isTier2.value, isTrue);

    // symmetric layout: on by default, the switch gives the previous layout
    expect(c.isSymmetric.value, isTrue);
    expect(network().networkSymmetric, isTrue);
    expect(find.text('Symmetric layout: on (network)'), findsOneWidget);
    await tester.tap(find.byType(Switch).at(2));
    await tester.pump(_step);
    expect(c.isSymmetric.value, isFalse);
    expect(network().networkSymmetric, isFalse);
    expect(find.text('Symmetric layout: off (network)'), findsOneWidget);
    await tester.tap(find.byType(Switch).at(2));
    await tester.pump(_step);
    expect(c.isSymmetric.value, isTrue);

    // full width crop is the default; the switch shows the original viewBox
    expect(c.isCropped.value, isTrue);
    expect(
      tester.widgetList<OnboardingArt>(find.byType(OnboardingArt)).every((w) => w.window == OnboardingArtWindow.crop),
      isTrue,
    );
    await tester.tap(find.byType(Switch).last);
    await tester.pump(_step);
    expect(c.isCropped.value, isFalse);
    expect(
      tester.widgetList<OnboardingArt>(find.byType(OnboardingArt)).every((w) => w.window == OnboardingArtWindow.original),
      isTrue,
    );
    expect(find.text('Original viewBox'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await tester.pump(_step);
    expect(c.backdrop.value, LabBackdrop.dark);
  });
}
