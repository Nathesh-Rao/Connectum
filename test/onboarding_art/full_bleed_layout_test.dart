import 'dart:io';

import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/widgets/onboarding_art/onboarding_art.dart';
import 'package:connectum/core/widgets/onboarding_art/onboarding_art_palette.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/features/debug_onboarding/debug_onboarding_binding.dart';
import 'package:connectum/features/debug_onboarding/debug_onboarding_controller.dart';
import 'package:connectum/features/debug_onboarding/debug_onboarding_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Store implements SessionStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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

Future<void> _settle(WidgetTester t, [int steps = 6]) async {
  for (var i = 0; i < steps; i++) {
    await t.pump(_step);
  }
}

Finder get _paintBox => find
    .descendant(of: find.byType(OnboardingArt), matching: find.byType(AspectRatio))
    .first;

void main() {
  setUpAll(_loadFonts);

  setUp(() {
    Get.testMode = true;
    Get.put<SessionStore>(_Store());
  });
  tearDown(Get.reset);

  /// Pumps the debug onboarding at [size] and returns every Flutter error.
  Future<List<String>> pump(WidgetTester tester, Size size) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: AppRoutes.debugOnboarding,
        getPages: [
          GetPage(
            name: AppRoutes.debugOnboarding,
            page: () => const DebugOnboardingView(),
            binding: DebugOnboardingBinding(),
          ),
        ],
      ),
    );
    await _settle(tester);
    FlutterError.onError = previous;
    return errors;
  }

  // the network shows its symmetric layout by default (its own crop window)
  Rect window(OnboardingArtKind k) =>
      k.cropWindow(k.build(OnboardingArtPalette.authored).viewBox, symmetric: true);

  for (final width in [360.0, 411.0]) {
    testWidgets('the art is as wide as the screen at ${width.toInt()} dp', (tester) async {
      final errors = await pump(tester, Size(width, 900));
      expect(errors, isEmpty);
      final box = _paintBox;
      expect(tester.getSize(box).width, closeTo(width, 0.01));
      expect(tester.getTopLeft(box).dx, closeTo(0, 0.01));
      expect(tester.getTopRight(box).dx, closeTo(width, 0.01));
    });
  }

  testWidgets('on a tablet width the art is capped at 600 dp and centred', (tester) async {
    final errors = await pump(tester, const Size(800, 1280));
    expect(errors, isEmpty);
    final box = _paintBox;
    expect(tester.getSize(box).width, closeTo(600, 0.01));
    expect(tester.getTopLeft(box).dx, closeTo(100, 0.01));
  });

  testWidgets('the paint box has the crop window ratio on every page (no distortion)', (tester) async {
    await pump(tester, const Size(411, 900));
    final c = Get.find<DebugOnboardingController>();
    for (var i = 0; i < 3; i++) {
      final kind = [OnboardingArtKind.network, OnboardingArtKind.buildings, OnboardingArtKind.shield][i];
      c.goTo(i);
      await _settle(tester, 8);
      final s = tester.getSize(_paintBox);
      final w = window(kind);
      expect(s.width / s.height, closeTo(w.width / w.height, 0.002), reason: kind.name);
      expect(s.width, closeTo(411, 0.01), reason: '${kind.name} is full width');
    }
  });

  // 320x568: the fixed content of this screen (136 dp copy box, buttons, gaps)
  // already overflows by 34 dp with the main OnboardingStage and page padding
  // (measured); the art slot must not add to it. 360x640 has none.
  for (final (size, allowed) in [
    (const Size(320, 568), 34.0),
    (const Size(360, 640), 0.0),
  ]) {
    testWidgets('overflow at ${size.width.toInt()}x${size.height.toInt()} is at most $allowed, art inside its slot', (tester) async {
      final errors = await pump(tester, size);
      final overflow = RegExp(r'overflowed by ([\d.]+) pixels');
      for (final e in errors) {
        final m = overflow.firstMatch(e);
        expect(m, isNotNull, reason: 'unexpected error: $e');
        expect(double.parse(m![1]!), lessThanOrEqualTo(allowed + 0.5), reason: e);
      }
      final art = tester.getRect(find.byType(OnboardingArt).first);
      final slot = tester.getRect(find.byType(PageView).first);
      expect(art.left, greaterThanOrEqualTo(slot.left - 0.01));
      expect(art.right, lessThanOrEqualTo(slot.right + 0.01));
      expect(art.top, greaterThanOrEqualTo(slot.top - 0.01));
      expect(art.bottom, lessThanOrEqualTo(slot.bottom + 0.01));
      final box = tester.getRect(_paintBox);
      expect(box.width, lessThanOrEqualTo(size.width + 0.01));
      expect(box.height, lessThanOrEqualTo(slot.height + 0.01), reason: 'the art slot itself does not overflow');
      expect(box.width, greaterThan(0));
      // never stretched: whatever the slot allows, the ratio is the crop's
      final w = window(OnboardingArtKind.network);
      expect(box.width / box.height, closeTo(w.width / w.height, 0.002));
    });
  }

  testWidgets('text and buttons keep the page padding', (tester) async {
    await pump(tester, const Size(411, 900));
    expect(tester.getTopLeft(find.text('Connectum')).dx, greaterThan(16));
    expect(tester.getTopLeft(find.text('All your conversations in one place')).dx, greaterThan(16));
  });
}
