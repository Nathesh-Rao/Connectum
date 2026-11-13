import 'dart:math' as math;
import 'dart:ui';

import 'generated/shield_art_data.dart';
import 'onboarding_art_math.dart';
import 'onboarding_art_palette.dart';
import 'svg_path_parser.dart';
import 'svg_scene.dart';

/// Straight port of shield-security.html `render(t)` (viewBox 1774x887).
class ShieldSecurity {
  ShieldSecurity._();

  static const cycle = 3.9;
  static const loopStart = 1.95;

  static SvgScene build(Color Function(Color) remap) =>
      SvgScene.fromArt(shieldArt, remap: remap);

  /// Binds the scene to its frame function.
  static ArtScene bind(SvgScene scene) {
    final s = _ShieldFrame(scene);
    return ArtScene(
      render: s.render,
      staticT: loopStart,
      duration: loopStart + 3 * cycle,
      info: {'arrival': s.tArr, 'loopStart': loopStart, 'cycle': cycle},
    );
  }
}

class _Centre {
  _Centre(this.g)
    : cx = g.getBBox().center.dx,
      cy = g.getBBox().center.dy;

  final SvgNode g;
  final double cx, cy;
}

class _Ring {
  const _Ring(this.r, this.dot, this.w, this.c, this.o, [this.dash]);

  final double r;
  final bool dot;
  final double w;
  final Color c;
  final double o;
  final String? dash;
}

class _Spark {
  _Spark(this.g, this.ang, this.delay, this.reach, this.tilt);

  final SvgNode g;
  final double ang, delay, reach, tilt;
}

class _Chip {
  _Chip(this.g, this.cx, this.cy, this.plain, this.cipher);

  final SvgNode g;
  final double cx, cy;
  final SvgNode plain, cipher;
}

class _ShieldFrame {
  _ShieldFrame(this.scene) {
    _build();
  }

  final SvgScene scene;
  static const double cx0 = 887, cy0 = 458;
  static const msgScale = .58, encScale = .46;
  static const cycle = ShieldSecurity.cycle, loopStart = ShieldSecurity.loopStart;
  static const inX0 = -260.0, inDur = 1.1;
  static const encStart = 1.55, encDur = 1.7, encX1 = 1900.0;
  static const waveBreathe = 6.0, waveSpeed = 1.6;
  static const msgC = [281.5, 454.0], encC = [1491.0, 454.0];

  late final List<_Ring> rings;
  late final SvgNode sh, core, coreSpin, coreDot, barRect, msg, msgT, enc, encT;
  late final SvgNode encLock, packetIn, packetOut, pulseRing, fx, waves;
  late final List<SvgNode> variants, encAccent, ringEls;
  late final List<_Centre> asts, nodes, chevL, chevR;
  late final List<_Spark> sparksIn, sparksOut;
  late final List<_Chip> chips;
  late final double tArr;
  late final double halfMsg;
  late final double vmax;

  Color _m(Color c) => scene.remap(c);

  static const _nodeAt = [
    [3, -.9],
    [2, -2.4],
    [4, 2.2],
  ];

  void _build() {
    rings = [
      const _Ring(262, false, 3.5, OnboardingArtPalette.shieldMist, .9),
      const _Ring(297, true, 6, OnboardingArtPalette.shieldSky, .75, '0.1 17'),
      const _Ring(333, false, 2.5, OnboardingArtPalette.shieldSky, .8),
      const _Ring(370, true, 6, OnboardingArtPalette.shieldViolet, .7, '0.1 19'),
      const _Ring(408, false, 2.5, OnboardingArtPalette.shieldMist, .55),
    ];
    sh = scene.byId('shield');
    core = scene.byId('core');
    coreSpin = scene.byId('coreSpin');
    coreDot = scene.byId('coreDot');
    barRect = scene.byId('barRect');
    msg = scene.byId('msg');
    msgT = scene.byId('msgT');
    enc = scene.byId('enc');
    encT = scene.byId('encT');
    encLock = scene.byId('encLock');
    packetIn = scene.byId('packetIn');
    packetOut = scene.byId('packetOut');
    pulseRing = scene.byId('pulseRing');
    fx = scene.byId('fx');
    waves = scene.byId('waves');
    variants = [scene.byId('msgA'), scene.byId('msgB'), scene.byId('msgC')];
    asts = [for (var i = 0; i < 6; i++) _Centre(scene.byId('a$i'))];
    nodes = [for (var i = 0; i < 3; i++) _Centre(scene.byId('n$i'))];
    chevL = [for (final n in [22, 19]) _Centre(scene.byId('p$n'))];
    chevR = [for (final n in [20, 21]) _Centre(scene.byId('p$n'))];
    encAccent = [for (final n in [20, 21]) scene.byId('p$n')];

    ringEls = [
      for (final r in rings)
        scene.create('circle', {
          'cx': cx0,
          'cy': cy0,
          'stroke': r.c,
          'stroke-width': r.w,
          'stroke-opacity': r.o,
          if (r.dot) 'stroke-dasharray': r.dash!,
        }, waves),
    ];

    sparksIn = _mkSparks(16, 0, math.pi * 2 * 15 / 16, OnboardingArtPalette.shieldCyan);
    sparksOut = _mkSparks(9, -1.1, 1.1, OnboardingArtPalette.shieldViolet);

    chips = [
      for (final g in scene.byClass('chip'))
        _Chip(
          g,
          double.parse(g.data['cx']!),
          double.parse(g.data['cy']!),
          _descendant(g, 'plain'),
          _descendant(g, 'cipher'),
        ),
    ];

    final dist = cx0 - inX0;
    vmax = 1.5 * dist / inDur;
    halfMsg = (361 / 2) * msgScale;
    var tA = 0.0;
    for (var ct = 0.0; ct < inDur; ct += .002) {
      if (_msgX(ct) + halfMsg >= 689) {
        tA = ct;
        break;
      }
    }
    tArr = tA;
  }

  SvgNode _descendant(SvgNode n, String cls) {
    for (final c in n.children) {
      if (c.classes.contains(cls)) return c;
    }
    throw StateError('no .$cls');
  }

  SvgNode _glyph(String ch, Color color) {
    final g = scene.create('g', {
      'visibility': 'hidden',
      'fill': 'none',
      'stroke': color,
      'stroke-width': 3,
      'stroke-linecap': 'round',
      'stroke-linejoin': 'round',
    }, fx);
    if (ch == '0') {
      scene.create('ellipse', {'rx': 6.5, 'ry': 10.5}, g);
    } else {
      scene.create('path', {'d': 'M-6 -5 L1.5 -11 V11'}, g);
    }
    return g;
  }

  List<_Spark> _mkSparks(int n, double a0, double a1, Color color) => [
    for (var i = 0; i < n; i++)
      _Spark(
        _glyph((i * 7 + 3) % 2 != 0 ? '1' : '0', color),
        lerp(a0, a1, n == 1 ? .5 : i / (n - 1)) + ((i * 37) % 11 - 5) * .012,
        ((i * 13) % 7) * .03,
        .78 + ((i * 29) % 10) * .05,
        (((i * 53) % 9) - 4) * 4.0,
      ),
  ];

  double _ringR(int i, double t, double kick, double amp) =>
      rings[i].r * (1 + kick) +
      waveBreathe * math.sin(waveSpeed * t - i * .9) +
      amp;

  double _msgX(double ct) => lerp(inX0, cx0, eInOutCubic(clamp01(ct / inDur)));

  double _msgV(double ct) =>
      (_msgX(ct + .01) - _msgX(ct - .01)).abs() / .02 / vmax;

  double _encX(double ue) => lerp(cx0, encX1, eInOutCubic(clamp01(ue / encDur)));

  double _encV(double ue) =>
      (_encX(ue + .01) - _encX(ue - .01)).abs() /
      .02 /
      (1.5 * (encX1 - cx0) / encDur);

  void _chevScale(List<_Centre> list, double x, double base) {
    for (final c in list) {
      c.g.transform = xf(
        c.cx,
        c.cy,
        base * (1 + .45 * math.exp(-math.pow((x - c.cx) / 80, 2))),
      );
    }
  }

  void _burst(List<_Spark> list, double p, double r0, double reach) {
    for (final s in list) {
      final pp = clamp01((p - s.delay) / (1 - s.delay));
      if (p <= 0 || pp >= 1 || pp <= 0) {
        s.g.visible = false;
        continue;
      }
      final r = r0 + reach * s.reach * eOutCubic(pp);
      final sc = lerp(1.5, .85, pp);
      final op = pp < .12 ? pp / .12 : 1 - clamp01((pp - .5) / .5);
      s.g.visible = true;
      s.g.opacity = round2(op);
      s.g.transform = Tf.identity
          .translate(
            round2(cx0 + math.cos(s.ang) * r),
            round2(cy0 + math.sin(s.ang) * r),
          )
          .rotate(s.tilt)
          .scale(round2(sc));
    }
  }

  void _renderChips(double ct) {
    for (var i = 0; i < chips.length; i++) {
      final c = chips[i];
      final pin = ct < 0 ? 0.0 : eOutBack(clamp01((ct - .6 - i * .05) / .3), 2.6);
      final fp = clamp01((ct - 1.0 - i * .09) / .24);
      final pout = clamp01((ct - 1.4 - i * .04) / .2);
      final sc = math.max(0.0, pin * (1 - eInCubic(pout)));
      if (sc <= .001 || pout >= 1) {
        c.g.display = false;
        continue;
      }
      c.g.display = true;
      final flipped = fp >= .5;
      c.plain.display = !flipped;
      c.cipher.display = flipped;
      final sy = math.max(.02, math.cos(math.pi * fp).abs());
      final hop = -12 * math.sin(math.pi * fp);
      c.g.transform = Tf.identity
          .translate(c.cx, c.cy + round2(hop))
          .scale(round2(sc), round2(sc * sy))
          .translate(-c.cx, -c.cy);
    }
  }

  void render(double tIn) {
    final t = tIn < 0 ? 0.0 : tIn;
    final tI = math.min(t, loopStart);
    var shieldK = eOutBack(clamp01((tI - .05) / .65), 2.1);
    double ua = -1, ue = -1, ct = -1;
    var v = 0;
    if (t >= loopStart) {
      final u = t - loopStart;
      final k = (u / cycle).floor();
      ct = u - k * cycle;
      v = ((k % 3) + 3) % 3;
      ua = ct - tArr;
      ue = ct - encStart;
    }
    shieldK *= 1 + spring(ua, .05, 9, 30) + spring(ue, .028, 9, 30);
    sh.opacity = clamp01((tI - .05) / .08);
    sh.transform = xf(cx0, cy0, shieldK);

    var coreK = eOutBack(clamp01((tI - .45) / .45), 2.6);
    if (ct >= 0) {
      coreK *= ct < .55
          ? 1
          : ct < .75
          ? 1 - eInCubic((ct - .55) / .2)
          : ct < 1.55
          ? 0
          : eOutBack(clamp01((ct - 1.55) / .4), 2.2);
    }
    coreK = math.max(0.0, coreK) * (1 + .06 * math.sin(2 * math.pi * t / 1.7));
    core.display = coreK > .01;
    core.transform = xf(887, 456, coreK);
    coreSpin.transform = xf(887, 456, 1, t * 50);
    coreDot.r = round2(15 + 3 * math.sin(2 * math.pi * t / 1.7 + 1));

    final lit = ua < 0
        ? 0.0
        : ua < .1
        ? ua / .1
        : ua < .26
        ? 1.0
        : math.max(0.0, 1 - (ua - .26) / .4);
    final pa = ue < 0
        ? 0.0
        : ue < .12
        ? ue / .12
        : math.max(0.0, 1 - (ue - .12) / .7);
    for (var i = 0; i < rings.length; i++) {
      final rg = rings[i];
      final p = eOutBack(clamp01((tI - (.5 + i * .09)) / .5), 1.8);
      final el = ringEls[i];
      el.display = p > .01;
      if (p <= .01) continue;
      final ui = ua - .07 * i, uo = ue - .07 * i;
      final kick = spring(ui, .045, 7, 20) + spring(uo, .028, 7, 20);
      final amp =
          (ui > 0 ? 11 * math.exp(-3.4 * ui) * math.cos(13 * ui) : 0) +
          (uo > 0 ? 7 * math.exp(-3.4 * uo) * math.cos(13 * uo) : 0);
      el.r = round2(math.max(0.0, _ringR(i, t, kick, amp.toDouble())) * p);
      el.strokeOpacity = round2(rg.o * clamp01(p));
      el.stroke = rg.c == OnboardingArtPalette.shieldViolet
          ? mixColor(_m(OnboardingArtPalette.shieldViolet), _m(OnboardingArtPalette.shieldVioletPulse), pa)
          : mixColor(_m(rg.c), _m(OnboardingArtPalette.shieldCyan), lit * .85);
    }
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final p = eOutBack(clamp01((tI - (1.15 + i * .1)) / .4), 3);
      final ring = _nodeAt[i][0].toInt();
      final th = _nodeAt[i][1].toDouble();
      final ui = ua - .07 * ring, uo = ue - .07 * ring;
      final kick = spring(ui, .045, 7, 20) + spring(uo, .028, 7, 20);
      final amp =
          (ui > 0 ? 11 * math.exp(-3.4 * ui) * math.cos(13 * ui) : 0) +
          (uo > 0 ? 7 * math.exp(-3.4 * uo) * math.cos(13 * uo) : 0);
      final r = _ringR(ring, t, kick, amp.toDouble());
      final x = cx0 + r * math.cos(th), y = cy0 + r * math.sin(th);
      final s = math.max(0.0, p) * .8;
      n.g.display = p > 0;
      n.g.transform = Tf.identity
          .translate(round2(x), round2(y))
          .scale(round2(s))
          .translate(-n.cx, -n.cy);
    }

    final bw = eOutCubic(clamp01((tI - 1.0) / .5)) * 1774;
    barRect.x = round2(cx0 - bw / 2);
    barRect.width = round2(bw);
    final chevBase = eOutBack(clamp01((tI - 1.35) / .4), 2.4);

    if (t < loopStart) {
      msg.visible = false;
      enc.visible = false;
      packetIn.visible = false;
      packetOut.visible = false;
      pulseRing.opacity = 0;
      _renderChips(-1);
      _burst(sparksIn, 0, 0, 0);
      _burst(sparksOut, 0, 0, 0);
      for (final e in encAccent) {
        e.fill = _m(OnboardingArtPalette.shieldViolet);
      }
      _chevScale(chevL, -9999, chevBase);
      _chevScale(chevR, -9999, chevBase);
      return;
    }

    final inView = ct < inDur + .02;
    msg.visible = inView;
    var mx = -9999.0;
    if (inView) {
      for (var i = 0; i < variants.length; i++) {
        variants[i].display = i == v;
      }
      mx = _msgX(ct);
      final pop = .55 + .45 * eOutBack(clamp01(ct / .3), 2.4);
      final vn = _msgV(ct);
      msgT.transform = Tf.identity
          .translate(round2(mx), 458)
          .scale(
            round2(msgScale * pop * (1 + .12 * vn)),
            round2(msgScale * pop * (1 - .07 * vn)),
          )
          .translate(-msgC[0], -msgC[1]);
      final left = mx - halfMsg;
      final a = eOutCubic(clamp01(ct / .2)) * (1 - clamp01((ct - (tArr + .02)) / .1));
      final x0 = math.max(-40.0, left - 170 * a);
      final x1 = math.min(689.0, left - 10);
      packetIn.visible = a > .01 && x1 > x0;
      packetIn.x = round2(x0);
      packetIn.width = round2(math.max(0.0, x1 - x0));
    } else {
      packetIn.visible = false;
    }

    final pr = clamp01(ua / .65);
    pulseRing.r = round2(lerp(236, 345, eOutCubic(pr)));
    pulseRing.opacity = ua > 0 && ua < .65 ? round2(.9 * (1 - pr)) : 0;
    _burst(sparksIn, ua / .7, 238, 150);
    _renderChips(ct);

    final ep = clamp01(ue / encDur);
    final ex = _encX(ue);
    final encOn = ue > 0 && ep < 1;
    enc.visible = encOn;
    var exx = -9999.0;
    if (encOn) {
      exx = ex;
      final pop = .25 + .75 * eOutBack(clamp01(ue / .38), 2.4);
      final vn = _encV(ue);
      encT.transform = Tf.identity
          .translate(round2(ex), 458)
          .scale(
            round2(encScale * pop * (1 + .1 * vn)),
            round2(encScale * pop * (1 - .06 * vn)),
          )
          .translate(-encC[0], -encC[1]);
      encLock.transform = xf(1362, 454, math.max(0.0, eOutBack(clamp01((ue - .12) / .35), 3)));
      final n = 6 - v;
      for (var i = 0; i < asts.length; i++) {
        final a = asts[i];
        final p = i < n ? eOutBack(clamp01((ue - .3 - i * .06) / .3), 3) : 0.0;
        a.g.display = p > 0;
        a.g.transform = xf(a.cx, a.cy, math.max(0.0, p));
      }
      final left = ex - (374 / 2) * encScale;
      final a = eOutCubic(clamp01(ue / .2)) * (1 - clamp01((ep - .85) / .15));
      final x0 = math.max(1085.0, left - 150 * a);
      final x1 = math.min(1840.0, left - 8);
      packetOut.visible = a > .01 && x1 > x0;
      packetOut.x = round2(x0);
      packetOut.width = round2(math.max(0.0, x1 - x0));
    } else {
      packetOut.visible = false;
    }
    _burst(sparksOut, ue / .7, 238, 140);
    final accent = mixColor(
      _m(OnboardingArtPalette.shieldViolet),
      _m(OnboardingArtPalette.shieldVioletPulse),
      pa,
    );
    for (final e in encAccent) {
      e.fill = accent;
    }
    _chevScale(chevL, mx, chevBase);
    _chevScale(chevR, exx, chevBase);
  }
}
