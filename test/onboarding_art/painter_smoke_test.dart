import 'dart:ui';

import 'package:connectum/core/widgets/onboarding_art/onboarding_art.dart';
import 'package:connectum/core/widgets/onboarding_art/onboarding_art_palette.dart';
import 'package:connectum/core/widgets/onboarding_art/svg_scene.dart';
import 'package:flutter_test/flutter_test.dart';

const _times = <OnboardingArtKind, List<double>>{
  OnboardingArtKind.shield: [0, 0.5, 1.2, 1.95, 2.6, 3.4, 5.9, 6.5, 9.9, 10.9, 13.65],
  OnboardingArtKind.network: [0, 1.0, 2.5, 3.6, 5, 7, 9, 12, 14.5, 15.9, 16.7],
  OnboardingArtKind.buildings: [0, 0.3, 1.0, 2.0, 3.5, 4.5, 6, 8, 10, 12],
};

Future<Image> _render(OnboardingArtKind kind, double t, {bool blue = false}) {
  final scene = kind.build(
    blue ? OnboardingArtPalette.purpleToBlue : OnboardingArtPalette.authored,
  );
  final art = kind.bind(scene);
  final renderer = SvgRenderer(scene);
  final rec = PictureRecorder();
  final canvas = Canvas(rec);
  final vb = scene.viewBox;
  const w = 400.0;
  final h = w * vb.height / vb.width;
  canvas.clipRect(Rect.fromLTWH(0, 0, w, h));
  canvas.scale(w / vb.width, h / vb.height);
  canvas.translate(-vb.left, -vb.top);
  art.render(t);
  renderer.paint(canvas);
  return rec.endRecording().toImage(w.round(), h.round());
}

Future<List<int>> _bytes(OnboardingArtKind kind, double t) async {
  final img = await _render(kind, t);
  final data = await img.toByteData();
  return data!.buffer.asUint8List();
}

void main() {
  for (final kind in OnboardingArtKind.values) {
    group('${kind.name} painter', () {
      for (final t in _times[kind]!) {
        test('renders at t=$t', () async {
          final img = await _render(kind, t);
          expect(img.width, 400);
        });
      }
      test('same t gives the same picture, in any order', () async {
        final a = await _bytes(kind, _times[kind]![4]);
        await _bytes(kind, _times[kind]![2]);
        final b = await _bytes(kind, _times[kind]![4]);
        expect(a, b);
      });
      test('the blue-only remap renders', () async {
        final img = await _render(kind, _times[kind]![5], blue: true);
        expect(img.height, greaterThan(0));
      });
      test('transparent background and nothing outside the viewBox', () async {
        final scene = kind.build(OnboardingArtPalette.authored);
        final art = kind.bind(scene);
        final renderer = SvgRenderer(scene);
        final vb = scene.viewBox;
        const w = 200.0;
        final h = w * vb.height / vb.width;
        final rec = PictureRecorder();
        final canvas = Canvas(rec);
        // a canvas larger than the art: the painter's clip keeps the margin empty
        canvas.translate(20, 20);
        canvas.clipRect(Rect.fromLTWH(0, 0, w, h));
        canvas.scale(w / vb.width, h / vb.height);
        canvas.translate(-vb.left, -vb.top);
        art.render(_times[kind]![5]);
        renderer.paint(canvas);
        final img = await rec
            .endRecording()
            .toImage((w + 40).round(), (h + 40).round());
        final px = (await img.toByteData())!.buffer.asUint8List();
        final width = img.width;
        int alpha(int x, int y) => px[(y * width + x) * 4 + 3];
        for (var x = 0; x < width; x++) {
          expect(alpha(x, 5), 0, reason: 'top margin');
          expect(alpha(x, img.height - 5), 0, reason: 'bottom margin');
        }
        for (var y = 0; y < img.height; y++) {
          expect(alpha(5, y), 0, reason: 'left margin');
          expect(alpha(width - 5, y), 0, reason: 'right margin');
        }
        expect(alpha(0, 0), 0, reason: 'corner is transparent');
      });
    });
  }
}
