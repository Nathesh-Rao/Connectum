import 'dart:math' as math;
import 'dart:ui';

import 'generated/buildings_art_data.dart';
import 'onboarding_art_math.dart';
import 'onboarding_art_palette.dart';
import 'svg_path_parser.dart';
import 'svg_scene.dart';

/// Straight port of buildings-switching.html `render(t)` (viewBox 1536x1024).
class BuildingsSwitching {
  BuildingsSwitching._();

  static SvgScene build(Color Function(Color) remap) =>
      SvgScene.fromArt(buildingsArt, remap: remap);

  static ArtScene bind(SvgScene scene) {
    final f = _BuildingsFrame(scene);
    return ArtScene(
      render: f.render,
      staticT: f.loop0 + 0.1,
      duration: f.loop0 + f.period,
      info: {
        'loopStart': f.loop0,
        'period': f.period,
        'nodeT': f.nodeT,
        'hits': [for (final h in f.hits) [h.t, h.icon]],
      },
    );
  }
}

Tf _tf(double x, double y, double s) =>
    Tf.identity.translate(x, y).scale(s).translate(-x, -y);

class _Plan {
  _Plan(this.kind, this.t0, this.t1, {this.a = 0, this.b = 0, this.s = 0});

  final String kind;
  final double t0, t1, a, b, s;
}

class _Bub {
  _Bub(this.el)
    : nx = double.parse(el.data['nx']!),
      ny = double.parse(el.data['ny']!),
      cx = double.parse(el.data['cx']!),
      cy = double.parse(el.data['cy']!);

  final SvgNode el;
  final double nx, ny, cx, cy;
}

class _BuildingsFrame {
  _BuildingsFrame(this.scene) {
    _build();
  }

  final SvgScene scene;

  static const groundD = 0.6;
  static const bStart = 0.45, bStep = 0.2, bDur = 0.42;
  static const nDur = 0.3, bDur2 = 0.5;
  static const rise = 300.0;
  static const hl0 = 0.95;
  static const iconBuilding = ['fa', 'tw', 'mu'];

  late final List<double> legLen, stops, arcStart, arcDur, nodeT, bub0;
  late final List<String> order;
  late final Map<String, double> basex;
  final groups = <String, List<SvgNode>>{};
  late final Map<String, SvgNode> tints;
  late final List<({SvgNode el, double x, double y})> nodes;
  late final List<_Bub> bubs;
  late final List<SvgNode> arcm;
  late final SvgNode particle, gRect, shG, shCk;
  late final PathMetric routeMetric;
  late final double routeLen, loop0, period;
  final plan = <_Plan>[];
  final hits = <({double t, int icon})>[];
  late final List<List<SvgNode>> gl;

  List<SvgNode> _desc(SvgNode root, String cls) {
    final out = <SvgNode>[];
    void walk(SvgNode n) {
      for (final c in n.children) {
        if (c.classes.contains(cls)) out.add(c);
        walk(c);
      }
    }

    walk(root);
    return out;
  }

  void _build() {
    final cfg = buildingsArtCfg;
    final legs = cfg['legs']! as List;
    legLen = [for (final l in legs) ((l as Map)['len']! as num).toDouble()];
    stops = [for (final s in cfg['stops']! as List) (s as num).toDouble()];
    order = [for (final o in cfg['order']! as List) o as String];
    basex = {
      for (final e in (cfg['basex']! as Map).entries) e.key as String: (e.value as num).toDouble(),
    };
    for (final n in order) {
      groups[n] = scene.byClass('bg-$n');
    }
    tints = {for (final k in ['fa', 'tw', 'mu']) k: scene.byId('tint_$k')};
    nodes = [
      for (final n in cfg['nodes']! as List)
        (
          el: scene.byId((n as List)[0] as String),
          x: (n[1] as num).toDouble(),
          y: (n[2] as num).toDouble(),
        ),
    ];
    bubs = [for (final n in ['bL', 'bC', 'bR']) _Bub(scene.byId(n))];
    arcm = scene.byClass('arcm');

    final st = <double>[], du = <double>[], nt = <double>[0.75];
    for (var i = 0; i < legLen.length; i++) {
      final s = nt[i] + 0.12;
      final d = 0.15 + legLen[i] / 900;
      st.add(s);
      du.add(d);
      nt.add(s + d);
    }
    arcStart = st;
    arcDur = du;
    nodeT = nt;
    bub0 = [nt[1] + 0.05, nt[2] + 0.05, nt[4] + 0.05];
    loop0 = nt[5] + 0.9;
    final route = scene.byId('route');
    routeMetric = route.pathData.computeMetrics().first;
    routeLen = routeMetric.length;
    particle = scene.byId('particle');
    gRect = scene.byId('gRect');

    const speed = 480.0, dwell = 0.55, edge = 0.35;
    final s = stops;
    final wp = <(double, double, Object)>[
      (s[0], edge, 'e'),
      (s[1], dwell, 0),
      (s[2], dwell, 1),
      (s[4], dwell, 2),
      (s[5], edge, 'e'),
      (s[4], dwell, 2),
      (s[2], dwell, 1),
      (s[1], dwell, 0),
      (s[0], edge, 'e'),
    ];
    var t = edge;
    plan.add(_Plan('in', 0, edge));
    for (var k = 1; k < wp.length; k++) {
      final dur = (wp[k].$1 - wp[k - 1].$1).abs() / speed;
      plan.add(_Plan('move', t, t + dur, a: wp[k - 1].$1, b: wp[k].$1));
      t += dur;
      if (wp[k].$3 == 'e') {
        if (k == wp.length - 1) {
          plan.add(_Plan('out', t, t + edge, s: wp[k].$1));
          t += edge;
        } else {
          t += 0.2;
        }
      } else {
        hits.add((t: t, icon: wp[k].$3 as int));
        t += wp[k].$2;
      }
    }
    period = t + 0.9;

    shG = scene.byId('shG');
    shCk = scene.byId('shCk');
    gl = [
      _desc(scene.byId('bL'), 'cell'),
      _desc(scene.byId('bC'), 'bar'),
      <SvgNode>[],
    ];
  }

  void _glyph(int k, double gt, double u) {
    if (k == 2) {
      final sp = eOutCubic(seg(gt, 0, 0.35));
      final cp = eOutCubic(seg(gt, 0.2, 0.35));
      final pulse = u >= 0 ? bump(clamp01(u / 0.6)) : 0.0;
      final cu = u >= 0 ? clamp01((u - 0.15) / 0.5) : 1.0;
      final cx = double.parse(shG.data['cx']!), cy = double.parse(shG.data['cy']!);
      shG.transform = _tf(cx, cy, math.max(0.001, (0.5 + 0.5 * sp) * (1 - 0.12 * pulse)));
      shG.opacity = sp;
      shCk.dashOffset = toFixed(1 - (u >= 0 ? eOutCubic(cu) : cp), 3);
      return;
    }
    for (final e in gl[k]) {
      final r = double.parse(e.data['r']!);
      final cx = double.parse(e.data['cx']!), cy = double.parse(e.data['cy']!);
      var s = eOutCubic(seg(gt, r * 0.4, 0.28));
      if (u >= 0) s *= 1 - 0.55 * bump(clamp01((u - r * 0.35) / 0.55));
      s = math.max(s, 0.001);
      e.transform = k == 0
          ? _tf(cx, cy, s)
          : Tf.identity.translate(0, cy).scale(1, s).translate(0, -cy);
    }
  }

  void render(double t) {
    final g = eOutCubic(seg(t, 0, groundD));
    final w = 1560 * g;
    gRect.x = 768 - w / 2;
    gRect.width = w;

    final lt = t - loop0;
    final lc = lt >= 0 ? lt % period : -1.0;
    final hl = [0.0, 0.0, 0.0];
    final hu = [-1.0, -1.0, -1.0];
    if (lc >= 0) {
      for (final h in hits) {
        final u = (lc - h.t) / hl0;
        hl[h.icon] = math.max(hl[h.icon], bump(u));
        if (u >= 0 && u < 1) hu[h.icon] = u;
      }
    }

    for (var k = 0; k < order.length; k++) {
      final n = order[k];
      final p = eOutCubic(seg(t, bStart + k * bStep, bDur));
      final dy = rise * (1 - p);
      final s = 0.96 + 0.04 * p;
      final ti = iconBuilding.indexOf(n);
      final h = ti >= 0 ? hl[ti] : 0.0;
      final sc = s * (1 + 0.012 * h);
      final tr = p <= 0
          ? Tf.identity.translate(0, 2000)
          : Tf.identity.translate(0, dy).then(_tf(basex[n]!, 856, sc));
      for (final e in groups[n]!) {
        e.transform = tr;
      }
      if (ti >= 0) {
        final e = tints[n]!;
        e.transform = tr;
        e.opacity = toFixed(0.5 * h, 3);
      }
    }

    for (var i = 0; i < arcm.length; i++) {
      final p = eInOutCubic(seg(t, arcStart[i], arcDur[i]));
      arcm[i].dashOffset = toFixed(legLen[i] * (1 - p), 2);
    }

    for (var k = 0; k < nodes.length; k++) {
      final nd = nodes[k];
      final p = eOutCubic(seg(t, nodeT[k] - 0.2, nDur));
      nd.el.opacity = p > 0 ? 1 : 0;
      nd.el.transform = _tf(nd.x, nd.y, 0.2 + 0.8 * p);
      if (p <= 0) nd.el.opacity = 0;
    }

    for (var k = 0; k < bubs.length; k++) {
      final b = bubs[k];
      final p = eOutCubic(seg(t, bub0[k], bDur2));
      final s = 0.82 + 0.18 * p;
      final hp = 1 + 0.08 * hl[k];
      b.el.opacity = toFixed(p, 3);
      b.el.transform = _tf(b.nx, b.ny, s).then(_tf(b.cx, b.cy, k == 2 ? 1 : hp));
      _glyph(k, t - bub0[k] - 0.2, hu[k]);
    }

    var op = 0.0;
    double? pos;
    var sc = 1.0;
    if (lc >= 0) {
      for (final st in plan) {
        if (lc < st.t0 || lc > st.t1) continue;
        final u = (lc - st.t0) / (st.t1 - st.t0);
        if (st.kind == 'in') {
          pos = stops[0];
          op = eOutCubic(u);
          sc = 0.4 + 0.6 * eOutCubic(u);
        } else if (st.kind == 'out') {
          pos = st.s;
          op = 1 - eOutCubic(u);
          sc = 1 - 0.6 * eOutCubic(u);
        } else {
          pos = st.a + (st.b - st.a) * eInOutCubic(u);
          op = 1;
        }
        break;
      }
      if (pos == null) {
        _Plan? last;
        for (final p in plan) {
          if (p.t1 <= lc) last = p;
        }
        if (last != null) {
          pos = last.kind == 'move'
              ? last.b
              : last.kind == 'in'
              ? stops[0]
              : null;
          op = pos == null ? 0 : 1;
        }
      }
    }
    if (pos != null && op > 0) {
      final pt = routeMetric.getTangentForOffset(clamp01(pos, 0, routeLen))!.position;
      particle.cx = toFixed(pt.dx, 2);
      particle.cy = toFixed(pt.dy, 2);
      particle.r = toFixed(9 * sc, 2);
      particle.opacity = toFixed(op, 3);
    } else {
      particle.opacity = 0;
    }
  }
}
