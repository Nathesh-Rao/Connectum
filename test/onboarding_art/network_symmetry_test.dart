import 'dart:typed_data';
import 'dart:ui';

import 'package:connectum/core/widgets/onboarding_art/network_tiers.dart';
import 'package:connectum/core/widgets/onboarding_art/onboarding_art.dart';
import 'package:connectum/core/widgets/onboarding_art/onboarding_art_palette.dart';
import 'package:connectum/core/widgets/onboarding_art/svg_scene.dart';
import 'package:connectum/core/widgets/onboarding_art_stage.dart';
import 'package:flutter_test/flutter_test.dart';

/// The network's mirror-symmetric layout: pixel symmetry at many times,
/// centring, pairs, the crop window and the seamless loop. No pumpAndSettle,
/// no widgets: the scene is rendered the way the painter draws it.
const _axis = kNetworkAxisX;
const _width = 1200; // axis at exactly px 600 of the symmetric window

class _Rig {
  _Rig({List<String>? visible}) {
    scene = OnboardingArtKind.network.build(OnboardingArtPalette.authored);
    art = visible == null
        ? OnboardingArtKind.network.bind(scene, symmetric: true)
        : NetworkIconsBind.bindSymmetric(scene, visible);
    renderer = SvgRenderer(scene);
    window = OnboardingArtKind.network.cropWindow(
      scene.viewBox,
      symmetric: true,
    );
    height = (_width * window.height / window.width).round();
  }

  late final SvgScene scene;
  late final ArtScene art;
  late final SvgRenderer renderer;
  late final Rect window;
  late final int height;

  double get period => art.duration;

  /// What the painter draws: the half, then the half flipped without the hub.
  Future<Uint8List> pixels(double t) async {
    final rec = PictureRecorder();
    final c = Canvas(rec);
    c.clipRect(Rect.fromLTWH(0, 0, _width.toDouble(), height.toDouble()));
    c.scale(_width / window.width, height / window.height);
    c.translate(-window.left, -window.top);
    art.render(t);
    renderer.paint(c);
    art.setMirrored!(true);
    c.translate(2 * _axis, 0);
    c.scale(-1, 1);
    renderer.paint(c);
    art.setMirrored!(false);
    final img = await rec.endRecording().toImage(_width, height);
    return (await img.toByteData())!.buffer.asUint8List();
  }
}

/// Binds with a user-edited list (the tests of "edit the list, keep symmetry").
class NetworkIconsBind {
  static ArtScene bindSymmetric(SvgScene s, List<String> visible) =>
      OnboardingArtKind.network.bindWith(s, visible);
}

/// Largest connected-ish region of differing pixels, as a box (coarse 20 px
/// cells), for the failure message.
String _worst(Uint8List a, int h, int tol) {
  var minX = _width, minY = h, maxX = -1, maxY = -1, count = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < _width; x++) {
      final i = (y * _width + x) * 4, j = (y * _width + (_width - 1 - x)) * 4;
      var d = 0;
      for (var k = 0; k < 4; k++) {
        final v = (a[i + k] - a[j + k]).abs();
        if (v > d) d = v;
      }
      if (d > tol) {
        count++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  return '$count pixels differ by more than $tol, in x $minX..$maxX, y $minY..$maxY';
}

/// Fails with the time and the largest differing region.
void _check(Uint8List px, int h, String when) {
  if (_differing(px, h, _channelTol) > 0) {
    fail('$when: ${_worst(px, h, _channelTol)}');
  }
  final soft = _differing(px, h, _softTol);
  if (soft > _pixelTol) fail('$when: ${_worst(px, h, _softTol)}');
}

int _differing(Uint8List a, int h, int tol) {
  var n = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < _width; x++) {
      final i = (y * _width + x) * 4, j = (y * _width + (_width - 1 - x)) * 4;
      for (var k = 0; k < 4; k++) {
        if ((a[i + k] - a[j + k]).abs() > tol) {
          n++;
          break;
        }
      }
    }
  }
  return n;
}

/// Tolerance. Skia's anti-aliasing is not exactly mirror-symmetric, so thin
/// edges differ a little (measured: at most 160 of 255 on a handful of pixels,
/// a real 1 px shift gives about 255):
/// no pixel may differ by more than this (of 255) ...
const _channelTol = 170;

/// ... and at most this many pixels of a 1200 x ~780 frame (0.09 percent) may
/// differ by more than [_softTol].
const _softTol = 48;
const _pixelTol = 800;

void main() {
  group('pixel symmetry (flip horizontally, compare)', () {
    final rig = _Rig();
    final times = <String, double>{
      'before anything': 0.0,
      'intro, hub pops in': 0.4,
      'upper pair spawns': 1.9,
      'lower pair spawns': 2.5,
      'badges thrown': 3.2,
      'tier 1 shown': 3.9,
      'tier 2 revealing': 4.7,
      'tier 2 revealed': 6.0,
      'electron on a hub link': 7.2,
      'electron on a kid link': 8.4,
      'all shown': 9.0,
      'idle bobbing': 10.1,
      'a spring peak (hub ripple)': 11.3,
      'loop mid': 7.7,
      'outro': 14.0,
      'loop end': 15.3,
    };
    for (final e in times.entries) {
      test('${e.key} (t=${e.value})', () async {
        final px = await rig.pixels(e.value);
        _check(px, rig.height, 't=${e.value}');
      });
    }

    test('many more times, every 0.37 s over two loops', () async {
      for (var t = 0.0; t < 2 * rig.period; t += 0.37) {
        final px = await rig.pixels(t);
        _check(px, rig.height, 't=${t.toStringAsFixed(2)}');
      }
    });

    test(
      'an edited left list keeps the symmetry (one small person removed)',
      () async {
        final edited = [
          for (final id in kNetworkSymVisiblePersons)
            if (id != 'll-1' && id != 'lr-1') id,
        ];
        final r = _Rig(visible: edited);
        for (final t in [6.0, 9.0]) {
          final px = await r.pixels(t);
          _check(px, r.height, 't=$t');
        }
        final ids = (r.art.info['people']! as List)
            .map((p) => (p as List)[6])
            .toSet();
        expect(ids.contains('ll-1'), isFalse);
        expect(ids.contains('ll-0'), isTrue);
      },
    );
  });

  group('centring', () {
    final rig = _Rig();

    test(
      'the drawn content is centred on the axis, left and right margins are equal',
      () async {
        final px = await rig.pixels(rig.art.staticT);
        var minX = _width, maxX = -1, minY = rig.height, maxY = -1;
        for (var y = 0; y < rig.height; y++) {
          for (var x = 0; x < _width; x++) {
            if (px[(y * _width + x) * 4 + 3] > 24) {
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
            }
          }
        }
        // 1200 px stand for the full width; on a 360 dp phone 1 dp = 3.33 px
        const dp = _width / 360;
        final left = minX.toDouble(), right = (_width - 1 - maxX).toDouble();
        expect(left, greaterThan(0), reason: 'no clipping at the left edge');
        expect(right, greaterThan(0), reason: 'no clipping at the right edge');
        expect(
          (left - right).abs(),
          lessThanOrEqualTo(dp),
          reason: 'margins $left / $right px',
        );
        expect(
          ((minX + maxX) / 2 - (_width - 1) / 2).abs(),
          lessThanOrEqualTo(dp),
        );
        // about 2 percent of the width at each side (safe margin) at the worst
        expect(left, greaterThan(_width * 0.01));
      },
    );

    test('vertically: the revealed picture is centred in the window', () async {
      final px = await rig.pixels(rig.art.staticT);
      var minY = rig.height, maxY = -1;
      for (var y = 0; y < rig.height; y++) {
        for (var x = 0; x < _width; x++) {
          if (px[(y * _width + x) * 4 + 3] > 24) {
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
      final top = minY.toDouble(), bottom = (rig.height - 1 - maxY).toDouble();
      // 1 dp on a 360 dp wide phone is 3.33 px; the transients (pulses, ripples)
      // may take a little more room below than above, never more than 3 percent
      expect(
        (top - bottom).abs(),
        lessThanOrEqualTo(rig.height * 0.03),
        reason: 'space above $top px, below $bottom px',
      );
    });

    test(
      'the window is symmetric about the axis and holds the crop margin',
      () {
        final w = rig.window;
        expect((w.left + w.right) / 2, closeTo(_axis, 1e-6));
        expect(w.left, greaterThanOrEqualTo(rig.scene.viewBox.left));
        expect(w.right, lessThanOrEqualTo(rig.scene.viewBox.right));
      },
    );

    test('the decor orbs of the debug stage are mirrored and not clipped', () {
      for (final width in [320.0, 360.0, 390.0, 411.0, 600.0]) {
        final rects = OnboardingArtStage.networkOrbRects(width);
        for (final r in rects) {
          // the glow reaches 19 dp beyond the orb
          expect(r.left - 19, greaterThanOrEqualTo(0), reason: '$r at $width');
          expect(
            r.right + 19,
            lessThanOrEqualTo(width),
            reason: '$r at $width',
          );
          expect(r.top, greaterThanOrEqualTo(0), reason: '$r at $width');
          final mirror = Rect.fromLTRB(
            width - r.right,
            r.top,
            width - r.left,
            r.bottom,
          );
          expect(
            rects.any(
              (o) =>
                  (o.left - mirror.left).abs() < 1e-9 &&
                  (o.top - mirror.top).abs() < 1e-9 &&
                  (o.width - mirror.width).abs() < 1e-9,
            ),
            isTrue,
            reason: 'no mirror of $r at $width',
          );
        }
      }
    });
  });

  group('pairs', () {
    final rig = _Rig();
    final people = (rig.art.info['people']! as List).cast<List>();
    final byId = {for (final p in people) p[6] as String: p};

    test(
      'the config: every left id has a mirror, counts per side are equal',
      () {
        expect(kNetworkMirrorPairs.keys, [
          ...kNetworkLeftTier1Persons,
          ...kNetworkLeftTier2Persons,
        ]);
        expect(
          kNetworkMirrorPairs.values.toSet().length,
          kNetworkMirrorPairs.length,
        );
        expect(
          kNetworkMirrorPairs.keys.toSet().intersection(
            kNetworkMirrorPairs.values.toSet(),
          ),
          isEmpty,
        );
        final visible = kNetworkSymVisiblePersons;
        expect(visible.length, 1 + 2 * kNetworkMirrorPairs.length);
        expect(
          visible.where(kNetworkMirrorPairs.containsKey).length,
          visible.where(kNetworkMirrorPairs.containsValue).length,
        );
        expect(kNetworkMirrorPairs['ul'], 'ur');
        expect(kNetworkMirrorPairs['ll-1'], 'lr-1');
      },
    );

    test(
      'left persons are left of the axis, mirrors are at the mirrored position',
      () {
        for (final id in kNetworkMirrorPairs.keys) {
          final p = byId[id]!;
          expect(p[4] as double, lessThan(_axis), reason: id);
          final mx = 2 * _axis - (p[4] as double);
          expect(mx, greaterThan(_axis));
        }
        // heights per row: the pair shares one
        expect(byId['ul']![5], kNetworkRowY['upper']);
        expect(byId['ll']![5], kNetworkRowY['lower']);
        expect(byId['ul']![4], _axis - kNetworkRowDx['upper']!);
      },
    );

    test(
      'a pair shares its reveal time (it is the same element, drawn twice)',
      () {
        // the mirrored partner is the left element flipped by the painter, so
        // it cannot start at another time; the pixel tests above prove it
        for (final id in kNetworkMirrorPairs.keys) {
          expect(byId.containsKey(id), isTrue);
          expect(
            byId.containsKey(kNetworkMirrorPairs[id]),
            isFalse,
            reason: 'the right half is not built',
          );
        }
      },
    );

    test('badges: both persons of a pair share the badge of the row map', () {
      final badges = (rig.art.info['badges']! as List).cast<List>();
      expect(badges.length, kNetworkLeftTier1Persons.length);
      for (final b in badges) {
        final row = kNetworkMidRow[b[0]]!;
        expect(
          b[1],
          kNetworkBadgeArt[kNetworkBadgeByPair[row]!],
          reason: b[0] as String,
        );
        // the badge is on the outer (left) side of its person
        expect(b[2] as double, lessThan(byId[b[0]]![4] as double));
      }
    });

    test(
      'no orphan connector: every link joins two drawn people, ends on their rings',
      () {
        final conn = (rig.art.info['connectors']! as List).cast<List>();
        expect(conn.length, people.length);
        final ids = {'c', ...byId.keys};
        for (final c in conn) {
          expect(ids.contains(c[0]), isTrue, reason: 'from ${c[0]}');
          expect(ids.contains(c[1]), isTrue, reason: 'to ${c[1]}');
          final to = byId[c[1]]!;
          // the end is near the person it goes to
          final d =
              Offset(c[6] as double, c[7] as double) -
              Offset(to[4] as double, to[5] as double);
          expect(d.distance, lessThan(140), reason: '${c[0]} -> ${c[1]}');
          // drawn outward from the hub: the start is nearer the hub than the end
          final hub = const Offset(_axis, 710);
          expect(
            (Offset(c[4] as double, c[5] as double) - hub).distance,
            lessThan((Offset(c[6] as double, c[7] as double) - hub).distance),
          );
        }
      },
    );

    test(
      'no mask hole, no baked leftovers: the old links, avatars and badges are gone',
      () {
        for (final k in ['top', 'tr', 'br', 'bl', 'l', 'ch']) {
          expect(rig.scene.findMasked('mk_$k'), isNull, reason: 'mk_$k');
          expect(rig.scene.maybeId('av_$k')?.parent, isNull, reason: 'av_$k');
          expect(rig.scene.maybeId('ic_$k')?.parent, isNull, reason: 'ic_$k');
        }
      },
    );

    test(
      'nothing of the left half reaches over the axis (the flip would double it)',
      () {
        final hub = (rig.art.info['hubOnly']! as List).cast<SvgNode>();
        for (var t = 0.0; t < rig.period; t += 1 / 31) {
          rig.art.render(t);
          for (final d in rig.renderer.drawnRects()) {
            if (d.via.any(hub.contains)) continue;
            expect(
              d.rect.right,
              lessThanOrEqualTo(_axis + 1e-6),
              reason:
                  '${d.label} (${d.node.tag}) at t=${t.toStringAsFixed(2)} is ${d.rect}',
            );
          }
        }
      },
    );
  });

  group('crop window and loop', () {
    final rig = _Rig();

    test(
      'every visible element, and its mirror, stays inside the window over the whole loop',
      () {
        final vb = rig.scene.viewBox;
        var checked = 0;
        for (var t = 0.0; t <= 2 * rig.period; t += 1 / 37) {
          rig.art.render(t);
          for (final d in rig.renderer.drawnRects()) {
            if (!d.rect.overlaps(vb)) continue;
            final r = d.rect.intersect(vb);
            if (r.isEmpty) continue;
            final m = Rect.fromLTRB(
              2 * _axis - r.right,
              r.top,
              2 * _axis - r.left,
              r.bottom,
            );
            for (final q in [r, m]) {
              checked++;
              const eps = 1e-6;
              if (q.left < rig.window.left - eps ||
                  q.right > rig.window.right + eps ||
                  q.top < rig.window.top - eps ||
                  q.bottom > rig.window.bottom + eps) {
                fail(
                  '${d.label} at t=${t.toStringAsFixed(2)} is $q, outside ${rig.window}',
                );
              }
            }
          }
        }
        expect(checked, greaterThan(1000));
      },
    );

    test(
      'the loop is seamless: empty at the start and the end, equal one period later',
      () async {
        final start = await rig.pixels(0);
        final end = await rig.pixels(rig.period - 0.001);
        int alpha(Uint8List p) {
          var s = 0;
          for (var i = 3; i < p.length; i += 4) {
            s += p[i];
          }
          return s;
        }

        int maxAlpha(Uint8List p) {
          var m = 0;
          for (var i = 3; i < p.length; i += 4) {
            if (p[i] > m) m = p[i];
          }
          return m;
        }

        // the hub's glow starts at opacity 0.015 on t = 0 (as in the HTML)
        expect(
          maxAlpha(start),
          lessThan(12),
          reason: 'the first frame is empty',
        );
        expect(alpha(end), lessThan(1000), reason: 'the last frame is empty');
        final a = await rig.pixels(7.3);
        final b = await rig.pixels(7.3 + rig.period);
        final c = await rig.pixels(7.3 + 3 * rig.period);
        expect(b, a);
        expect(c, a);
      },
    );

    test('the loop length is the old one (14.881 s, outro at 13.681 s)', () {
      expect(rig.period, closeTo(14.881, 0.002));
      expect(rig.art.info['outroStart'], closeTo(13.681, 0.002));
      expect(rig.art.info['idleTrim'], kNetworkIdleTrim);
    });

    test('symmetric off is the previous layout', () {
      final s = OnboardingArtKind.network.build(OnboardingArtPalette.authored);
      final old = OnboardingArtKind.network.bind(s);
      expect(old.mirrorAxis, isNull);
      expect(old.info['visible'], kNetworkVisiblePersons);
    });
  });
}
