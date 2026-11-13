import 'dart:math' as math;
import 'dart:ui';

import 'generated/network_art_data.dart';
import 'onboarding_art_math.dart';
import 'network_tiers.dart';
import 'onboarding_art_palette.dart';
import 'svg_path_parser.dart';
import 'svg_scene.dart';

part 'network_symmetric_frame.dart';

/// Straight port of network-icons.html `render(t)` (viewBox -430 -290 2400 1600).
class NetworkIcons {
  NetworkIcons._();

  /// The loop length of the HTML (full network).
  static const htmlPeriod = 16.8;

  static SvgScene build(Color Function(Color) remap) =>
      SvgScene.fromArt(networkArt, remap: remap);

  /// The mirror-symmetric layout (see network_tiers.dart): the left half is
  /// built, the painter draws it twice.
  static ArtScene bindSymmetric(
    SvgScene scene, {
    List<String>? visible,
    double idleTrim = kNetworkIdleTrim,
  }) {
    final list = visible ?? kNetworkSymVisiblePersons;
    final f = _SymFrame(scene, list, idleTrim);
    return ArtScene(
      render: f.render,
      staticT: f.out0 - 1.1,
      duration: f.period,
      mirrorAxis: kNetworkAxisX,
      setMirrored: f.setMirrored,
      info: {
        // [level, kind, t0, ts, x, y, id] of the left half; level 0 = mid persons
        'people': [
          for (final m in f.mids) [0, m.person, m.start, m.spawnT, m.cx, m.cy, m.id],
          for (final n in f.nodes) [n.lvl, n.k, n.t0, n.ts, n.x, n.y, n.pid],
        ],
        // [from, to, drawn from, arrives at, x1, y1, x2, y2]
        'connectors': [
          for (final m in f.mids)
            ['c', m.id, m.start, m.start + _SymFrame.ld, m.hubPa[0], m.hubPa[1], m.hubPb[0], m.hubPb[1]],
          for (final n in f.nodes)
            [n.par!.pid, n.pid, n.t0, n.t0 + 0.5, n.pa[0], n.pa[1], n.pb[0], n.pb[1]],
        ],
        // [id, badge art, x, y] of the left badges
        'badges': [for (final m in f.mids) [m.id, m.badgeArt, m.badgeAt[0], m.badgeAt[1]]],
        'mirrorPairs': kNetworkMirrorPairs,
        'visible': list,
        'period': f.period,
        'outroStart': f.out0,
        'idleTrim': idleTrim,
        'introEnd': f.introEnd,
        'electronStarts': [for (final q in f.e) q.t0],
        'pulses': f.cps.length,
        'personGroups': {
          for (final m in f.mids) m.id: m.av,
          for (final n in f.nodes) n.pid: n.g,
        },
        'hubOnly': f.hubOnly,
      },
    );
  }

  static ArtScene bind(
    SvgScene scene, {
    List<String> visible = kNetworkVisiblePersons,
    double idleTrim = kNetworkIdleTrim,
  }) {
    final f = _NetworkFrame(scene, visible, idleTrim);
    return ArtScene(
      render: f.render,
      // everything is up just before the outro (the HTML uses 14.5 of 15.6)
      staticT: f.out0 - 1.1,
      duration: f.period,
      info: {
        // [level, kind, t0, ts, x, y, id]
        'people': [
          for (final n in f.nodes.where((n) => n.hasDom))
            [n.lvl, n.k, n.t0, n.ts, n.x, n.y, n.pid],
        ],
        // [from, to, drawn from, arrives at]: hub links to the small people
        // and the links between small people
        'connectors': [
          for (final n in f.nodes.where((n) => n.hasDom))
            [n.par!.pid, n.pid, n.t0, n.t0 + 0.5, n.pa[0], n.pa[1], n.pb[0], n.pb[1]],
          for (final l in f.lat)
            [
              l.a,
              l.b,
              l.t0,
              l.t0 + 0.7,
              l.el.x1,
              l.el.y1,
              l.el.x2,
              l.el.y2,
            ],
        ],
        'nodes': f.nodes.length,
        'electrons': f.e.length,
        'lateral': f.lat.length,
        'visible': visible,
        'period': f.period,
        'outroStart': f.out0,
        'idleTrim': idleTrim,
        'introEnd': f.introEnd,
        'electronStarts': [for (final q in f.e) q.t0],
        'pulses': f.cps.length,
        // the group that draws each small person, by id
        'personGroups': {
          for (final n in f.nodes.where((n) => n.hasDom)) n.pid: n.g,
        },
      },
    );
  }
}

typedef _P = List<double>;


_P _pt(Object? o) => [for (final e in o! as List) (e as num).toDouble()];

double _cbrt(double x) => x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

double _eo(double u) => eOutCubic(u);

double _eio(double u) => eInOutCubic(u);

double _back(double x, double c1) => eOutBack(x, c1);

Tf _tf(double x, double y, double s, [double dy = 0, double rot = 0, double dx = 0]) =>
    Tf.identity
        .translate(dx, dy)
        .translate(x, y)
        .rotate(rot)
        .scale(s)
        .translate(-x, -y);

_P _edge(_P c, double rx, double ry, double tx, double ty) {
  var dx = tx - c[0], dy = ty - c[1];
  final l = math.sqrt(dx * dx + dy * dy);
  final len = l == 0 ? 1.0 : l;
  dx /= len;
  dy /= len;
  final r = (rx * ry) / math.sqrt(math.pow(ry * dx, 2) + math.pow(rx * dy, 2));
  return [c[0] + dx * r, c[1] + dy * r];
}

class _Node {
  _Node(this.k, this.x, this.y, this.s, this.lvl, this.par, this.id, this.ord);

  final String k;
  final double x, y, s;
  final int lvl;
  final _Node? par;
  final int id, ord;
  final List<_Node> kids = [];
  double t0 = 0, ts = 0, len = 0;
  late _P pa, pb;
  late SvgNode line, dot, head, g, rip;
  bool hasDom = false;

  /// `top`, `top-0`, `top-0-1`, ...
  String pid = '';
  bool isShown = false;
}

class _Sfx {
  _Sfx(this.flash, this.rip, this.dots);

  final SvgNode flash;
  final List<SvgNode> rip, dots;
}

class _Comet {
  _Comet(this.g, this.streak, this.halo, this.head);

  final SvgNode g, streak, halo, head;
}

class _Ifx {
  _Ifx(this.glow, this.rings, this.stars);

  final SvgNode glow;
  final List<SvgNode> rings, stars;
}

class _Lat {
  _Lat(this.t0, this.len, this.el, this.a, this.b);

  final double t0, len;
  final SvgNode el;
  final String a, b;
}

class _Seg {
  _Seg(this.a, this.b, this.t0, this.d, this.sc);

  final _P a, b;
  final double t0, d, sc;
}

class _Slot {
  _Slot(this.g, this.trail, this.halo, this.head);

  final SvgNode g, halo, head;
  final List<SvgNode> trail;
}

class _NetworkFrame {
  _NetworkFrame(this.scene, this.visible, this.idleTrim) {
    _build();
  }

  final SvgScene scene;
  final List<String> visible;
  final double idleTrim;

  static const htmlOut0 = 15.6, outD = 0.7;

  /// Outro start and loop length of this configuration (set when built).
  late final double out0, period, introEnd;
  late final List<String> vk; // visible outer people
  late final List<String> all; // visible people including the centre
  late final bool hasCh;
  late final Map<String, _P> nodeXYv;
  static const keys = ['top', 'tr', 'br', 'bl', 'l'];
  static const cyan = OnboardingArtPalette.networkCyan;
  static const white = Color.fromARGB(255, 255, 255, 255);

  static const ring = <String, List<Object>>{
    'c': [770.0, 710.0, 240.0, 72.0, OnboardingArtPalette.networkDeep],
    'top': [697.0, 298.0, 130.0, 41.0, OnboardingArtPalette.networkDeep],
    'tr': [1171.0, 483.0, 132.0, 44.0, OnboardingArtPalette.networkViolet],
    'br': [1158.0, 915.0, 130.0, 44.0, OnboardingArtPalette.networkBlue],
    'bl': [280.0, 916.0, 132.0, 45.0, OnboardingArtPalette.networkViolet],
    'l': [305.0, 478.0, 135.0, 45.0, OnboardingArtPalette.networkSky],
  };
  static const glowCol = <String, Color>{
    'top': OnboardingArtPalette.networkBlue,
    'tr': OnboardingArtPalette.networkViolet,
    'br': OnboardingArtPalette.networkBlue,
    'bl': OnboardingArtPalette.networkViolet,
    'l': OnboardingArtPalette.networkSky,
  };
  static const head = <String, _P>{
    'top': [703, 177],
    'tr': [1175, 363],
    'br': [1155, 790],
    'bl': [278, 790],
    'l': [296, 354],
  };
  static const ls = <String, double>{'top': 1.2, 'tr': 1.4, 'br': 1.6, 'bl': 1.8, 'l': 2.0};
  static const ld = 0.75;
  static const ch0 = 3.1, chd = 0.85;
  static const nodeXY = <String, _P>{
    'tr': [995, 557],
    'br': [986, 812],
    'bl': [518, 806],
    'l': [507, 561],
    'ch': [535, 371],
  };
  static const kinds = ['l', 'tr', 'top', 'br', 'bl'];
  static const sc = [1.0, 0.58, 0.36, 0.22];
  static const lenL = [0.0, 300.0, 200.0, 130.0];
  static const opa = [1.0, 0.92, 0.74, 0.56];
  static const base = [0.0, 4.1, 5.0, 5.8];
  static const mir = {'l': 'tr', 'tr': 'l', 'bl': 'br', 'br': 'bl', 'top': 'top'};
  static const spreads = [0.0, 0.6, 0.36, 0.0];

  late final Map<String, List<_P>> cn;
  late final Map<String, _P> icPos;
  late final Map<String, double> spawnT, throwT, nodeT;
  late final Map<String, List<double>> lnk;
  final av = <String, SvgNode>{};
  final ic = <String, SvgNode>{};
  final cm = <String, ({SvgNode e, double len})>{};
  late final SvgNode backG, front, flow, bgL, bgA, sceneG;
  final sfx = <String, _Sfx>{};
  final cmt = <String, _Comet>{};
  final nrip = <String, SvgNode>{};
  final flowL = <String, SvgNode>{};
  final ifx = <String, _Ifx>{};
  final nodes = <_Node>[];
  final prim = <String, _Node>{};
  final lat = <_Lat>[];
  final e = <_Seg>[];
  final slots = <_Slot>[];
  late final List<({double t, double sc, SvgNode e})> erip;
  late final List<({double t, SvgNode e})> cps;
  final orderCnt = [0, 0, 0, 0];
  static const slotCount = 9;

  void _build() {
    vk = [for (final k in keys) if (visible.contains(k)) k];
    all = [if (visible.contains('c')) 'c', ...vk];
    // the chat link joins the left and the top person
    hasCh = visible.contains('l') && visible.contains('top');
    nodeXYv = {
      for (final en in nodeXY.entries)
        if (en.key == 'ch' ? hasCh : vk.contains(en.key)) en.key: en.value,
    };
    _removeStatic();
    final cfgCn = networkArtCfg['cn']! as Map;
    cn = {for (final k in cfgCn.keys) k as String: [for (final p in cfgCn[k] as List) _pt(p)]};
    final cfgIc = networkArtCfg['ic']! as Map;
    icPos = {for (final k in cfgIc.keys) k as String: _pt(cfgIc[k])};
    spawnT = {'c': 0.0, for (final k in keys) k: ls[k]! + ld - 0.15};
    throwT = {for (final k in keys) k: spawnT[k]! + 0.35};
    lnk = {for (final k in vk) k: [ls[k]!, ld], if (hasCh) 'ch': [ch0, chd]};

    for (final k in all) {
      av[k] = scene.byId('av_$k');
    }
    for (final k in vk) {
      ic[k] = scene.byId('ic_$k');
    }
    for (final k in [...vk, if (hasCh) 'ch']) {
      final n = scene.byId('cm_$k');
      cm[k] = (e: n, len: n.dash![0]);
    }
    backG = scene.byId('fxBack');
    front = scene.byId('fxFront');
    flow = scene.byId('flow');
    bgL = scene.byId('bgLinks');
    bgA = scene.byId('bgAv');
    sceneG = scene.byId('scene');

    for (final k in all) {
      final r = ring[k]!;
      final cx = r[0] as double, cy = r[1] as double;
      final rx = r[2] as double, ry = r[3] as double;
      final col = r[4] as Color;
      final flash = scene.create('ellipse', {
        'cx': cx, 'cy': cy, 'rx': rx * 1.1, 'ry': ry * 1.6,
        'fill': col, 'opacity': 0, 'filter': 'url(#blur)',
      }, backG);
      final rip = <SvgNode>[
        for (var i = 0; i < 3; i++)
          scene.create('ellipse', {
            'cx': cx, 'cy': cy, 'rx': rx, 'ry': ry, 'fill': 'none',
            'stroke': i == 1 ? cyan : col, 'stroke-width': 5, 'opacity': 0,
          }, backG),
      ];
      final n = k == 'c' ? 14 : 9;
      final dots = <SvgNode>[
        for (var i = 0; i < n; i++)
          scene.create('circle', {
            'r': 5, 'fill': i % 2 != 0 ? cyan : col, 'opacity': 0,
          }, front),
      ];
      sfx[k] = _Sfx(flash, rip, dots);
    }
    for (final k in lnk.keys) {
      final g = scene.create('g', {'opacity': 0, 'filter': 'url(#glow)'}, front);
      cmt[k] = _Comet(
        g,
        scene.create('line', {
          'stroke': cyan, 'stroke-width': 7, 'stroke-linecap': 'round', 'opacity': .9,
        }, g),
        scene.create('circle', {'r': 13, 'fill': cyan, 'opacity': .55}, g),
        scene.create('circle', {'r': 6, 'fill': white}, g),
      );
    }
    for (final k in nodeXYv.keys) {
      nrip[k] = scene.create('circle', {
        'cx': nodeXYv[k]![0], 'cy': nodeXYv[k]![1], 'r': 14, 'fill': 'none',
        'stroke': cyan, 'stroke-width': 4, 'opacity': 0,
      }, front);
    }
    nodeT = {};
    for (final k in nodeXYv.keys) {
      final a = cn[k]![0], b = cn[k]![1], n = nodeXYv[k]!;
      final l = dist2(a, b);
      final f = clamp01(((n[0] - a[0]) * (b[0] - a[0]) + (n[1] - a[1]) * (b[1] - a[1])) / (l * l));
      final u = f < .5 ? _cbrt(f / 4) : 1 - _cbrt(2 * (1 - f)) / 2;
      nodeT[k] = lnk[k]![0] + u * lnk[k]![1];
    }
    for (final k in vk) {
      final a = cn[k]![0], b = cn[k]![1];
      flowL[k] = scene.create('line', {
        'x1': a[0], 'y1': a[1], 'x2': b[0], 'y2': b[1], 'stroke': white,
        'stroke-width': 3.5, 'stroke-linecap': 'round',
        'stroke-dasharray': '0.1 34', 'opacity': 0,
      }, flow);
    }
    for (final k in vk) {
      final x = icPos[k]![0], y = icPos[k]![1], col = glowCol[k]!;
      ifx[k] = _Ifx(
        scene.create('circle', {
          'cx': x, 'cy': y, 'r': 74, 'fill': col, 'opacity': 0, 'filter': 'url(#blur)',
        }, backG),
        [
          for (var i = 0; i < 2; i++)
            scene.create('circle', {
              'cx': x, 'cy': y, 'r': 50, 'fill': 'none',
              'stroke': i != 0 ? cyan : col, 'stroke-width': 4, 'opacity': 0,
            }, front),
        ],
        [
          for (var i = 0; i < 7; i++)
            scene.create('path', {
              'd': 'M0 -9 L2.6 -2.6 L9 0 L2.6 2.6 L0 9 L-2.6 2.6 L-9 0 L-2.6 -2.6Z',
              'fill': i % 2 != 0 ? cyan : col, 'opacity': 0,
            }, front),
        ],
      );
    }
    _buildBackground();
    _buildElectrons();
  }

  /// Drops the artwork of every person that is not visible: the avatar, its
  /// icon badge and the masked link graphics, plus the chat link when one of
  /// its two ends is gone.
  void _removeStatic() {
    for (final k in ['c', ...keys]) {
      if (visible.contains(k)) continue;
      scene.remove(scene.maybeId('av_$k'));
      scene.remove(scene.maybeId('ic_$k'));
      if (k != 'c') scene.remove(scene.findMasked('mk_$k'));
    }
    if (!hasCh) scene.remove(scene.findMasked('mk_ch'));
  }

  _Node _make(_Node p, double x, double y, String k, int lvl, int ord) {
    final nd = _Node(k, x, y, sc[lvl], lvl, p, nodes.length, ord);
    nd.t0 = base[lvl] + ord * 0.11;
    nd.ts = nd.t0 + 0.38;
    final rp = ring[p.k]!, rc = ring[k]!;
    nd.pa = _edge([p.x, p.y], (rp[2] as double) * p.s, (rp[3] as double) * p.s, x, y);
    nd.pb = _edge([x, y], (rc[2] as double) * nd.s, (rc[3] as double) * nd.s, p.x, p.y);
    nd.len = dist2(nd.pa, nd.pb);
    nd.pid = '${p.pid}-${p.kids.length}';
    p.kids.add(nd);
    nodes.add(nd);
    return nd;
  }

  _P _clampP(double x, double y, double px) {
    if (y > 1185) {
      final sg = (x - px) == 0 ? 1.0 : (x - px).sign;
      x += sg * (y - 1185) * 1.4;
      y = 1185;
    }
    return [clamp01(x, -385, 1925), clamp01(y, -190, 1235)];
  }

  void _grow(_Node p, int lvl, [bool onlyFirst = false]) {
    final gp = p.par != null ? [p.par!.x, p.par!.y] : [770.0, 710.0];
    var dx = p.x - gp[0], dy = p.y - gp[1];
    final l = math.sqrt(dx * dx + dy * dy);
    dx /= l;
    dy /= l;
    final n = lvl == 3 ? 1 : (onlyFirst ? 1 : 2);
    for (var i = 0; i < n; i++) {
      final off = lvl == 3 ? 0.0 : (i != 0 ? 1 : -1) * spreads[lvl];
      final c = math.cos(off), s = math.sin(off), len = lenL[lvl];
      final rx0 = p.x + (dx * c - dy * s) * len;
      final ry0 = p.y + (dx * s + dy * c) * len;
      if (lvl >= 2 && (ry0 > 1185 || rx0 < -385 || rx0 > 1925)) continue;
      final xy = _clampP(rx0, ry0, p.x);
      final x = xy[0], y = xy[1];
      if (lvl >= 2 && nodes.any((o) => math.sqrt(math.pow(o.x - x, 2) + math.pow(o.y - y, 2)) < 75)) {
        continue;
      }
      final nd = _make(p, x, y, kinds[(kinds.indexOf(p.k) * 2 + i + lvl) % 5], lvl, orderCnt[lvl]++);
      if (lvl < 3) _grow(nd, lvl + 1);
    }
  }

  void _mirrorKids(_Node src, _Node dst) {
    for (final c in src.kids) {
      final nd = _make(dst, dst.x - (c.x - src.x), dst.y + (c.y - src.y), mir[c.k]!, c.lvl, c.ord);
      _mirrorKids(c, nd);
    }
  }

  void _buildBackground() {
    for (final k in keys) {
      final r = ring[k]!;
      final n = _Node(k, r[0] as double, r[1] as double, 1, 0, null, nodes.length, 0);
      n.pid = k;
      prim[k] = n;
      nodes.add(n);
    }
    _grow(prim['l']!, 1);
    _mirrorKids(prim['l']!, prim['tr']!);
    _grow(prim['bl']!, 1);
    _mirrorKids(prim['bl']!, prim['br']!);
    _grow(prim['top']!, 1, true);
    final top = prim['top']!;
    if (top.kids.isNotEmpty) {
      final c = top.kids[0];
      final nd = _make(top, top.x - (c.x - top.x), c.y, mir[c.k]!, 1, c.ord);
      _mirrorKids(c, nd);
    }
    // who shows: a hub by its key, a small person by its id (or all with
    // `background`), and only when its parent shows
    final listed = visible.contains('background');
    for (final n in nodes) {
      n.isShown = n.lvl == 0
          ? vk.contains(n.k)
          : (listed || visible.contains(n.pid)) && n.par!.isShown;
    }
    final nodeFill = <String, Color>{
      'l': cyan,
      'br': cyan,
      'tr': OnboardingArtPalette.networkViolet,
      'bl': OnboardingArtPalette.networkViolet,
      'top': OnboardingArtPalette.networkDeep,
    };
    for (final n in nodes.where((n) => n.lvl > 0 && n.isShown)) {
      final r = ring[n.k]!;
      final col = r[4] as Color;
      final w = 6 * math.pow(n.s, 0.8);
      n.line = scene.create('line', {
        'x1': n.pa[0], 'y1': n.pa[1], 'x2': n.pb[0], 'y2': n.pb[1], 'stroke': col,
        'stroke-width': w, 'stroke-linecap': 'round',
        'stroke-dasharray': '${n.len.toStringAsFixed(1)} ${(n.len + 5).toStringAsFixed(1)}',
        'stroke-dashoffset': n.len.toStringAsFixed(1), 'opacity': opa[n.lvl],
      }, bgL);
      final m = lerp2(n.pa, n.pb, 0.5);
      n.dot = scene.create('circle', {
        'cx': m[0], 'cy': m[1], 'r': 16 * n.s, 'fill': nodeFill[n.k]!, 'opacity': 0,
      }, bgL);
      n.head = scene.create('circle', {'r': 6 * n.s + 2, 'fill': cyan, 'opacity': 0}, bgL);
      n.g = scene.create('g', {'opacity': 0}, bgA);
      scene.create('use', {'href': '#s_${n.k}'}, n.g);
      n.rip = scene.create('ellipse', {
        'cx': n.x, 'cy': n.y, 'rx': (r[2] as double) * n.s, 'ry': (r[3] as double) * n.s,
        'fill': 'none', 'stroke': col, 'stroke-width': 3, 'opacity': 0,
      }, bgA);
      n.hasDom = true;
    }
    for (var i = 0; i < keys.length; i++) {
      final A = prim[keys[i]]!.kids, B = prim[keys[(i + 1) % 5]]!.kids;
      ({_Node a, _Node b, double d})? best;
      for (final a in A) {
        for (final b in B) {
          final d = dist2([a.x, a.y], [b.x, b.y]);
          if (best == null || d < best.d) best = (a: a, b: b, d: d);
        }
      }
      if (best == null || best.d > 520) continue;
      final a = best.a, b = best.b;
      // a link toward a hidden person is trimmed, it would dangle
      if (!a.isShown || !b.isShown) continue;
      final ra = [(ring[a.k]![2] as double) * a.s, (ring[a.k]![3] as double) * a.s];
      final rb = [(ring[b.k]![2] as double) * b.s, (ring[b.k]![3] as double) * b.s];
      final pa = _edge([a.x, a.y], ra[0], ra[1], b.x, b.y);
      final pb = _edge([b.x, b.y], rb[0], rb[1], a.x, a.y);
      final len = dist2(pa, pb);
      lat.add(_Lat(5.0 + i * 0.12, len, scene.create('line', {
        'x1': pa[0], 'y1': pa[1], 'x2': pb[0], 'y2': pb[1],
        'stroke': OnboardingArtPalette.networkSky, 'stroke-width': 3,
        'stroke-linecap': 'round',
        'stroke-dasharray': '${len.toStringAsFixed(1)} ${(len + 5).toStringAsFixed(1)}',
        'stroke-dashoffset': len.toStringAsFixed(1), 'opacity': 0.55,
      }, bgL), a.pid, b.pid));
    }
  }

  double _pushSeg(_P a, _P b, double t0, double s) {
    final d = math.max(0.34, dist2(a, b) / 330);
    e.add(_Seg(a, b, t0, d, s));
    return t0 + d;
  }

  void _buildElectrons() {
    final leaves = nodes.where((n) => n.lvl == 3).toList()
      ..sort((a, b) => math.atan2(a.y - 710, a.x - 770).compareTo(math.atan2(b.y - 710, b.x - 770)));
    final picks = [0, 5, 2, 7, 4, 9, 1, 6, 3, 8]
        .map((i) => (i * leaves.length / 10 + .5).floor())
        .toList();
    const r0 = 6.9, rStep = 0.55;
    const depths = [4, 3, 4, 2, 4, 3, 4, 4, 3, 4];
    // where the HTML's last electron effect ends (the loop tail keeps that gap)
    var htmlEnd = 0.0;
    var activityEnd = 0.0;
    for (var ri = 0; ri < picks.length; ri++) {
      final leaf = leaves[picks[ri] % leaves.length];
      final path = <_Node>[];
      for (_Node? n = leaf; n != null; n = n.par) {
        path.insert(0, n);
      }
      final p0 = path[0];
      // the HTML's own timing, for the tail only
      var th = r0 + ri * rStep;
      for (var i = 0; i < math.min(depths[ri], path.length); i++) {
        final a = i == 0 ? cn[p0.k]![0] : path[i].pa;
        final b = i == 0 ? cn[p0.k]![1] : path[i].pb;
        final end = th + math.max(0.34, dist2(a, b) / 330);
        htmlEnd = math.max(htmlEnd, end + 0.7);
        th = end + 0.1;
      }
      // what is kept: the first leg on a visible person's link; the legs
      // through the removed crowd only with the background
      if (!vk.contains(p0.k)) continue;
      var t = r0 - idleTrim + ri * rStep;
      t = _pushSeg(cn[p0.k]![0], cn[p0.k]![1], t, 1) + 0.1;
      // the legs outwards while the person at the end of the leg shows
      for (var i = 1; i < math.min(depths[ri], path.length); i++) {
        if (!path[i].isShown) break;
        t = _pushSeg(path[i].pa, path[i].pb, t, path[i].s) + 0.1;
      }
    }
    if (hasCh) _pushSeg(cn['ch']![0], cn['ch']![1], 8.0 - idleTrim, 1);
    htmlEnd = math.max(htmlEnd, 8.0 + math.max(0.34, dist2(cn['ch']![0], cn['ch']![1]) / 330) + 0.7);
    for (final q in e) {
      activityEnd = math.max(activityEnd, q.t0 + q.d + 0.7);
    }
    // intro: the last visible hub's icon has landed and its rings and stars are done
    var intro = 2.0;
    for (final k in vk) {
      intro = math.max(intro, throwT[k]! + 0.62 + 1.12);
    }
    // the small people have popped in and their links have drawn
    for (final n in nodes.where((n) => n.hasDom)) {
      intro = math.max(intro, n.ts + 0.6);
    }
    for (final l in lat) {
      intro = math.max(intro, l.t0 + 0.7);
    }
    introEnd = intro;
    // the outro keeps the HTML's gap after the last effect; the loop keeps its tail
    out0 = ((math.max(activityEnd, introEnd) + (htmlOut0 - htmlEnd)) * 1000).round() / 1000;
    period = ((out0 + (NetworkIcons.htmlPeriod - htmlOut0)) * 1000).round() / 1000;
    for (var i = 0; i < slotCount; i++) {
      final g = scene.create('g', {'opacity': 0, 'filter': 'url(#glow)'}, front);
      final trail = [
        for (var j = 0; j < 8; j++) scene.create('circle', {'r': 6, 'fill': cyan}, g),
      ];
      final halo = scene.create('circle', {'r': 17, 'fill': cyan, 'opacity': .5}, g);
      final hd = scene.create('circle', {'r': 8, 'fill': cyan, 'stroke': white, 'stroke-width': 3}, g);
      slots.add(_Slot(g, trail, halo, hd));
    }
    erip = [
      for (final q in e)
        (
          t: q.t0 + q.d,
          sc: q.sc,
          e: scene.create('circle', {
            'cx': q.b[0], 'cy': q.b[1], 'r': 10, 'fill': 'none', 'stroke': cyan,
            'stroke-width': 4 * math.max(.5, q.sc), 'opacity': 0,
          }, front),
        ),
    ];
    final cT = <double>[if (all.contains('c')) 1.0];
    for (var t = 3.8; t < out0 - 0.6; t += 2.3) {
      cT.add(t);
    }
    cps = [
      for (final t in cT)
        (
          t: t,
          e: scene.create('ellipse', {
            'cx': 770, 'cy': 710, 'rx': 240, 'ry': 72, 'fill': 'none',
            'stroke': cyan, 'stroke-width': 5, 'opacity': 0,
          }, backG),
        ),
    ];
  }

  void _spawn(String k, double t) {
    final u = t - spawnT[k]!;
    final o = sfx[k]!;
    final r = ring[k]!;
    final cx = r[0] as double, cy = r[1] as double;
    final rx = r[2] as double, ry = r[3] as double;
    final el = av[k]!;
    final p = u <= 0 ? 0.0 : _back(seg(u, 0, 0.7), 1.3);
    final q = _eo(seg(u, 0, 0.7));
    final idle = u > 0.9 ? math.sin(t * 1.35 + cx * 0.01) * 2.4 * _eo(seg(u, 0.9, 0.8)) : 0.0;
    el.opacity = toFixed(_eo(seg(u, 0, 0.22)), 3);
    el.transform = _tf(cx, cy, 0.4 + 0.6 * p, 46 * (1 - q) + idle);
    o.flash.opacity = toFixed(0.5 * bump(seg(u, -0.05, 0.9)), 3);
    o.flash.transform = _tf(cx, cy, 0.8 + 0.5 * seg(u, 0, 0.9));
    for (var i = 0; i < o.rip.length; i++) {
      final v = seg(u, 0.04 + i * 0.2, 1.0);
      final s = 0.55 + 1.1 * _eo(v);
      o.rip[i].opacity = toFixed(u > 0 && v < 1 ? 0.75 * (1 - v) : 0, 3);
      o.rip[i].transform = _tf(cx, cy, s);
    }
    for (var i = 0; i < o.dots.length; i++) {
      final n = o.dots.length;
      final a = (i / n) * math.pi * 2 + 0.3;
      final v = _eo(seg(u, 0.06, 0.85));
      final d = o.dots[i];
      d.cx = toFixed(cx + math.cos(a) * rx * (0.6 + 0.7 * v), 1);
      d.cy = toFixed(cy + math.sin(a) * ry * (0.6 + 0.9 * v) - 50 * v, 1);
      d.r = toFixed(6 * (1 - v), 2);
      d.opacity = u > 0 && v < 1 ? 1 : 0;
    }
  }

  void render(double tIn) {
    final t = ((tIn % period) + period) % period;
    final o = seg(t, out0, outD);
    sceneG.opacity = toFixed(1 - _eo(o), 3);
    sceneG.transform = _tf(770, 512, 1 - 0.03 * _eo(o));

    for (final k in all) {
      _spawn(k, t);
    }

    for (final k in lnk.keys) {
      final s0 = lnk[k]![0], d = lnk[k]![1];
      final p = _eio(seg(t, s0, d));
      final a = cn[k]![0], b = cn[k]![1];
      final c = cmt[k]!;
      cm[k]!.e.dashOffset = toFixed(cm[k]!.len * (1 - p), 2);
      final vis = t > s0 && t < s0 + d + 0.12;
      c.g.opacity = vis ? toFixed(1 - seg(t, s0 + d, 0.12), 3) : 0;
      if (vis) {
        final h = lerp2(a, b, p);
        final tl = lerp2(a, b, math.max(0.0, p - 0.22));
        c.head.cx = h[0];
        c.head.cy = h[1];
        c.halo.cx = h[0];
        c.halo.cy = h[1];
        c.streak.x1 = tl[0];
        c.streak.y1 = tl[1];
        c.streak.x2 = h[0];
        c.streak.y2 = h[1];
      }
    }
    for (final k in nrip.keys) {
      final v = seg(t, nodeT[k]!, 0.7);
      nrip[k]!.opacity = toFixed(t > nodeT[k]! && v < 1 ? 0.85 * (1 - v) : 0, 3);
      nrip[k]!.r = toFixed(12 + 40 * _eo(v), 1);
    }
    for (final k in flowL.keys) {
      final f = flowL[k]!;
      final on = _eo(seg(t, ls[k]! + ld + 0.6, 0.8)) * (1 - _eo(o));
      f.opacity = toFixed(0.8 * on, 3);
      f.dashOffset = toFixed(-t * 26, 1);
    }

    for (final k in vk) {
      final el = ic[k]!, f = ifx[k]!;
      final x = icPos[k]![0], y = icPos[k]![1], s = head[k]!;
      final u = t - throwT[k]!;
      final on = u > 0;
      final v = seg(u, 0, 0.8);
      final ev = _eo(v);
      final dx = (s[0] - x) * (1 - ev);
      final dy = (s[1] - y) * (1 - ev) - 70 * math.sin(math.pi * ev);
      final fl = on ? math.sin(t * 1.6 + x * 0.02) * 3 * _eo(seg(u, 0.9, 0.7)) : 0.0;
      final scl = (0.15 + 0.85 * (on ? _back(v, 1.6) : 0)) * (1 + 0.05 * bump(seg(u, 0.7, 0.55)));
      el.opacity = toFixed(_eo(seg(u, 0, 0.15)), 3);
      el.transform = _tf(x, y, scl, dy + fl, -22 * (1 - ev), dx);
      final l = t - (throwT[k]! + 0.62);
      final rest = 0.22 * _eo(seg(l, 0.2, 0.8)) * (0.82 + 0.18 * math.sin(t * 1.9 + y * 0.01));
      f.glow.opacity = l > 0
          ? toFixed(math.min(1.0, 0.42 * bump(seg(l, 0, 1.0)) + rest) * (1 - _eo(o)), 3)
          : 0;
      f.glow.transform = _tf(x, y, 0.6 + 0.6 * _eo(seg(l, 0, 0.9)), fl);
      for (var i = 0; i < f.rings.length; i++) {
        final w = seg(l, i * 0.22, 0.9);
        f.rings[i].opacity = toFixed(l > 0 && w < 1 ? 0.7 * (1 - w) : 0, 3);
        f.rings[i].r = toFixed(44 + 62 * _eo(w), 1);
      }
      for (var i = 0; i < f.stars.length; i++) {
        final st = f.stars[i];
        final w = _eo(seg(l, (i % 3) * 0.05, 0.8));
        final a = i * (math.pi * 2 / 7) + 0.4;
        final d = 52 + 56 * w + (i % 2) * 12;
        st.opacity = l > 0 && w < 1 ? 1 : 0;
        st.transform = Tf.identity
            .translate(toFixed(x + math.cos(a) * d, 1), toFixed(y + math.sin(a) * d * 0.9, 1))
            .rotate(w * 70)
            .scale(toFixed(1.8 * (1 - w) + 0.1, 2));
      }
    }

    for (final n in nodes) {
      if (!n.hasDom) continue;
      final lp = _eio(seg(t, n.t0, 0.5));
      final u = t - n.ts;
      final rr = ring[n.k]!;
      final rcx = rr[0] as double, rcy = rr[1] as double;
      n.line.dashOffset = toFixed(n.len * (1 - lp), 1);
      n.line.opacity = toFixed(opa[n.lvl] * (1 - _eo(o)), 3);
      final hv = t > n.t0 && t < n.t0 + 0.62;
      n.head.opacity = hv ? toFixed(1 - seg(t, n.t0 + 0.5, 0.12), 2) : 0;
      if (hv) {
        final h = lerp2(n.pa, n.pb, lp);
        n.head.cx = toFixed(h[0], 1);
        n.head.cy = toFixed(h[1], 1);
      }
      final dp = _back(seg(u, 0, 0.6), 1.2);
      final dq = _eo(seg(u, 0, 0.6));
      final dd = _eo(seg(t, n.t0 + 0.3, 0.4));
      n.dot.opacity = toFixed(dd * opa[n.lvl] * (1 - _eo(o)), 3);
      n.dot.transform = _tf(n.dot.cx, n.dot.cy, 0.4 + 0.6 * dd);
      final idle = u > 0.8 ? math.sin(t * 1.2 + n.id * 0.9) * 2 * n.s * _eo(seg(u, 0.8, 0.8)) : 0.0;
      final sc2 = n.s * (0.4 + 0.6 * (u > 0 ? dp : 0));
      n.g.transform = Tf.identity
          .translate(n.x, n.y + 40 * n.s * (1 - dq) + idle)
          .scale(toFixed(sc2, 3))
          .translate(-rcx, -rcy);
      n.g.opacity = toFixed(opa[n.lvl] * _eo(seg(u, 0, 0.2)) * (1 - _eo(o)), 3);
      final rv = seg(u, 0.03, 0.9);
      n.rip.opacity = toFixed(u > 0 && rv < 1 ? 0.6 * (1 - rv) : 0, 3);
      n.rip.transform = _tf(n.x, n.y, 0.6 + 1.0 * _eo(rv));
    }
    for (final l in lat) {
      final p = _eio(seg(t, l.t0, 0.7));
      l.el.dashOffset = toFixed(l.len * (1 - p), 1);
      l.el.opacity = toFixed(0.55 * (1 - _eo(o)), 3);
    }

    var si = 0;
    for (final q in e) {
      if (t < q.t0 || t > q.t0 + q.d || si >= slotCount) continue;
      final s = slots[si++];
      final u = (t - q.t0) / q.d;
      final f = math.min(_eo(clamp01(u / 0.15)), 1 - _eo(clamp01((u - 0.88) / 0.12)));
      final k = 0.45 + 0.55 * q.sc;
      final h = lerp2(q.a, q.b, u);
      s.g.opacity = toFixed(f, 3);
      s.head.cx = toFixed(h[0], 1);
      s.head.cy = toFixed(h[1], 1);
      s.head.r = toFixed(8 * k, 2);
      s.halo.cx = toFixed(h[0], 1);
      s.halo.cy = toFixed(h[1], 1);
      s.halo.r = toFixed(17 * k, 2);
      for (var j = 0; j < s.trail.length; j++) {
        final c = s.trail[j];
        final w = math.max(0.0, u - (j + 1) * 0.035 * (dist2(q.a, q.b) > 150 ? 1 : 2));
        final p = lerp2(q.a, q.b, w);
        c.cx = toFixed(p[0], 1);
        c.cy = toFixed(p[1], 1);
        c.r = toFixed(7 * k * (1 - (j + 1) / 9), 2);
        c.opacity = toFixed(0.7 * (1 - (j + 1) / 9), 2);
      }
    }
    for (; si < slotCount; si++) {
      slots[si].g.opacity = 0;
    }
    for (final r in erip) {
      final v = seg(t, r.t, 0.7);
      final k = 0.5 + 0.5 * r.sc;
      r.e.opacity = toFixed(t > r.t && v < 1 ? 0.8 * (1 - v) : 0, 3);
      r.e.r = toFixed((10 + 34 * _eo(v)) * k, 1);
    }
    for (final c in cps) {
      final v = seg(t, c.t, 1.5);
      c.e.opacity = toFixed(t > c.t && v < 1 ? 0.4 * (1 - v) : 0, 3);
      c.e.transform = _tf(770, 710, 1 + 0.35 * _eo(v));
    }
  }
}
