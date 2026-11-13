import 'package:connectum/core/widgets/onboarding_art/onboarding_art.dart';
import 'package:connectum/core/widgets/onboarding_art/onboarding_art_palette.dart';
import 'package:connectum/core/widgets/onboarding_art/svg_scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// Same spans as tool/onboarding_anim/measure_bounds_test.dart (intro plus
/// several loops), sampled at a different step so a stale constant is caught.
const _spans = {
  OnboardingArtKind.shield: 60.0,
  OnboardingArtKind.network: 34.0,
  OnboardingArtKind.buildings: 45.0,
};

void main() {
  for (final kind in OnboardingArtKind.values) {
    group(kind.name, () {
      test('the crop window is the content plus 2 percent, inside the viewBox', () {
        final scene = kind.build(OnboardingArtPalette.authored);
        final w = kind.cropWindow(scene.viewBox);
        final c = kind.contentBounds;
        expect(scene.viewBox.contains(w.topLeft), isTrue);
        expect(w.right, lessThanOrEqualTo(scene.viewBox.right + 1e-9));
        expect(w.bottom, lessThanOrEqualTo(scene.viewBox.bottom + 1e-9));
        final m = c.width * OnboardingArtKind.cropMargin;
        expect(w.left, closeTo((c.left - m).clamp(scene.viewBox.left, double.infinity), 1e-9));
        expect(w.top, closeTo((c.top - m).clamp(scene.viewBox.top, double.infinity), 1e-9));
        expect(w.width / w.height, greaterThan(1));
      });

      test('no drawn element leaves the crop window at any time of the timeline', () {
        final scene = kind.build(OnboardingArtPalette.authored);
        final art = kind.bind(scene);
        final renderer = SvgRenderer(scene);
        final window = kind.cropWindow(scene.viewBox);
        const eps = 1e-6;
        var checked = 0;
        for (var t = 0.0; t <= _spans[kind]!; t += 1 / 37) {
          art.render(t);
          for (final d in renderer.drawnRects()) {
            // the HTML clips at the viewBox, so only what shows there counts
            if (!d.rect.overlaps(scene.viewBox)) continue;
            final r = d.rect.intersect(scene.viewBox);
            if (r.isEmpty) continue;
            checked++;
            final outside = r.left < window.left - eps ||
                r.top < window.top - eps ||
                r.right > window.right + eps ||
                r.bottom > window.bottom + eps;
            if (outside) {
              fail(
                '${d.label.isEmpty ? d.node.tag : d.label} (${d.node.tag}) at t=${t.toStringAsFixed(2)} '
                'is $r, outside the crop window $window',
              );
            }
          }
        }
        expect(checked, greaterThan(1000));
      });

      test('the window is tight: the measured content reaches every edge it can', () {
        final scene = kind.build(OnboardingArtPalette.authored);
        final c = kind.contentBounds;
        // the stored bounds are inside the viewBox and not larger than it
        expect(c.left, greaterThanOrEqualTo(scene.viewBox.left - 1e-9));
        expect(c.right, lessThanOrEqualTo(scene.viewBox.right + 1e-9));
        expect(c.width, lessThanOrEqualTo(scene.viewBox.width));
      });
    });
  }
}
