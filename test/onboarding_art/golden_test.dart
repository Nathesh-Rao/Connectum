import 'package:connectum/core/widgets/onboarding_art/onboarding_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Eyeball these against the HTML at the same `?t=`. Regenerate only these with
/// `flutter test --update-goldens test/onboarding_art/golden_test.dart`.
const _frames = <OnboardingArtKind, List<double>>{
  OnboardingArtKind.shield: [1.0, 1.95, 3.4, 8.5],
  // network (tier 1 + tier 2, 14.881 s loop): intro, tier 1 fully shown, tier 2
  // coming in, everything shown, an electron on a link, loop end
  OnboardingArtKind.network: [1.5, 3.6, 4.7, 6.0, 9.0, 14.5],
  // buildings: intro, all buildings, all icons and the particle in the loop
  OnboardingArtKind.buildings: [1.2, 4.0, 6.0, 8.0, 10.0],
};

/// The original-viewBox look, for the lab switch: one frame each.
const _original = <OnboardingArtKind, double>{
  OnboardingArtKind.shield: 3.4,
  OnboardingArtKind.network: 9.0,
  OnboardingArtKind.buildings: 8.0,
};

void main() {
  for (final e in _original.entries) {
    testWidgets('${e.key.name} original viewBox at t=${e.value}', (
      tester,
    ) async {
      await _golden(
        tester,
        e.key,
        e.value,
        OnboardingArtWindow.original,
        'original_',
      );
    });
  }
  for (final e in _frames.entries) {
    for (final t in e.value) {
      testWidgets('${e.key.name} at t=$t', (tester) async {
        await _golden(tester, e.key, t, OnboardingArtWindow.crop, '');
      });
    }
  }
}

Future<void> _golden(
  WidgetTester tester,
  OnboardingArtKind kind,
  double t,
  OnboardingArtWindow window,
  String tag,
) async {
  final c = OnboardingArtController();
  addTearDown(c.dispose);
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: Colors.white,
              child: SizedBox(
                width: 480,
                height: 320,
                child: OnboardingArt(kind: kind, controller: c, window: window),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  c.seek(t);
  await tester.pump();
  await expectLater(
    find.byKey(key),
    matchesGoldenFile('../goldens/onboarding_art/${kind.name}_${tag}t$t.png'),
  );
}
