import 'dart:ui';

import 'package:connectum/core/widgets/onboarding_art/generated/buildings_art_data.dart';
import 'package:connectum/core/widgets/onboarding_art/generated/network_art_data.dart';
import 'package:connectum/core/widgets/onboarding_art/generated/shield_art_data.dart';
import 'package:connectum/core/widgets/onboarding_art/svg_path_parser.dart';
import 'package:connectum/core/widgets/onboarding_art/svg_scene.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _paths(ArtEl el) => [
  if (el.tag == 'path' && el.attrs['d'] != null) el.attrs['d']!,
  for (final c in el.children) ..._paths(c),
];

void _expectRect(Rect r, double l, double t, double rt, double b) {
  expect(r.left, closeTo(l, 1e-6));
  expect(r.top, closeTo(t, 1e-6));
  expect(r.right, closeTo(rt, 1e-6));
  expect(r.bottom, closeTo(b, 1e-6));
}

void main() {
  group('real path data of the three animations', () {
    final cases = {
      'shield': (shieldArt, 50, const Rect.fromLTWH(-500, -500, 2800, 1900)),
      'network': (networkArt, 58, const Rect.fromLTWH(-800, -700, 3200, 2600)),
      'buildings': (buildingsArt, 117, const Rect.fromLTWH(-500, -500, 2600, 2000)),
    };
    for (final e in cases.entries) {
      test('${e.key}: every d string parses with sane bounds', () {
        final (art, count, limit) = e.value;
        final ds = _paths(art);
        expect(ds.length, count);
        for (final d in ds) {
          final p = parseSvgPath(d);
          expect(p.bounds.isEmpty, isFalse, reason: d);
          expect(limit.contains(p.bounds.topLeft), isTrue);
          expect(limit.contains(p.bounds.bottomRight), isTrue);
          final hull = p.path.getBounds();
          // tight bounds never exceed the control-point hull
          expect(p.bounds.left, greaterThanOrEqualTo(hull.left - 0.01));
          expect(p.bounds.right, lessThanOrEqualTo(hull.right + 0.01));
          expect(p.bounds.top, greaterThanOrEqualTo(hull.top - 0.01));
          expect(p.bounds.bottom, lessThanOrEqualTo(hull.bottom + 0.01));
        }
      });
    }

    test('the buildings legs and route from the script config parse', () {
      final legs = buildingsArtCfg['legs']! as List;
      for (final l in legs) {
        expect(parseSvgPath((l as Map)['d']! as String).bounds.isEmpty, isFalse);
      }
      expect(parseSvgPath(buildingsArtCfg['full']! as String).bounds.isEmpty, isFalse);
    });
  });

  group('syntax', () {
    test('absolute and relative lines, H and V', () {
      _expectRect(parseSvgPath('M10 20 L30 40').bounds, 10, 20, 30, 40);
      _expectRect(parseSvgPath('m10 20 l20 20').bounds, 10, 20, 30, 40);
      _expectRect(parseSvgPath('M0 0 H10 V5 h-4 v3').bounds, 0, 0, 10, 8);
    });

    test('compact numbers and implicit repeats', () {
      _expectRect(parseSvgPath('M1.5-2.3L4 5').bounds, 1.5, -2.3, 4, 5);
      _expectRect(parseSvgPath('M0 0 10 10 20 0').bounds, 0, 0, 20, 10);
      _expectRect(parseSvgPath('M0,0L.5.5').bounds, 0, 0, .5, .5);
      _expectRect(parseSvgPath('M0 0c1 1 2 2 3 3 1 1 1 1 1 1').bounds, 0, 0, 4, 4);
    });

    test('cubic bounds are tight, not the control hull', () {
      _expectRect(parseSvgPath('M0 0 C0 10 10 10 10 0').bounds, 0, 0, 10, 7.5);
    });

    test('S, Q and T', () {
      expect(parseSvgPath('M0 0 C0 5 5 5 5 0 S10 -5 10 0').bounds.isEmpty, isFalse);
      _expectRect(parseSvgPath('M0 0 Q5 10 10 0').bounds, 0, 0, 10, 5);
      expect(parseSvgPath('M0 0 Q5 10 10 0 T20 0').bounds.right, 20);
    });

    test('arcs, including compact flags', () {
      final r = parseSvgPath('M0 0 A10 10 0 0 1 20 0').bounds;
      _expectRect(r, 0, -10, 20, 0);
      final c = parseSvgPath('M0 0a10 10 0 0120 0').bounds;
      _expectRect(c, 0, -10, 20, 0);
    });

    test('Z closes and a new M starts a subpath', () {
      _expectRect(parseSvgPath('M0 0 L10 0 L10 10 Z m5 5 l1 1').bounds, 0, 0, 10, 10);
    });

    test('bad data throws', () {
      expect(() => parseSvgPath('L 1'), throwsFormatException);
      expect(() => parseSvgPath('M0 0 X1'), throwsFormatException);
    });
  });

  test('Tf composes in SVG list order and parses rotate(a cx cy)', () {
    final t = Tf.identity.translate(10, 0).scale(2);
    final r = t.mapRect(const Rect.fromLTWH(0, 0, 1, 1));
    _expectRect(r, 10, 0, 12, 2);
    final rot = Tf.parse('rotate(90 5 5)').mapRect(const Rect.fromLTWH(0, 0, 10, 10));
    _expectRect(rot, 0, 0, 10, 10);
    final a = Tf.parse('translate(3 4) scale(2)');
    final b = Tf.identity.translate(3, 4).scale(2);
    expect(a.e, b.e);
    expect(a.a, b.a);
  });
}
