part of 'network_icons_art.dart';

/// The symmetric network: only the LEFT half is built (the hub on the axis,
/// the left mid persons, their small people, the links and effects). The
/// painter draws it twice, the second time flipped about the axis with the
/// hub-owned nodes hidden, so the halves are the same pixels flipped.
class _SymFrame {
  _SymFrame(this.scene, this.visible, this.idleTrim) {
    _build();
  }

  final SvgScene scene;
  final List<String> visible;
  final double idleTrim;

  static const ring = _NetworkFrame.ring;
  static const glowCol = _NetworkFrame.glowCol;
  static const head = _NetworkFrame.head;
  static const sc = _NetworkFrame.sc;
  static const opa = _NetworkFrame.opa;
  static const base = _NetworkFrame.base;
  static const ld = _NetworkFrame.ld;
  static const cyan = _NetworkFrame.cyan;
  static const white = _NetworkFrame.white;
  static const slotCount = _NetworkFrame.slotCount;
  static const axis = kNetworkAxisX;

  /// Seconds between the end of the last effect and the outro; with this the
  /// loop keeps the previous layout's length (14.881 s, outro at 13.681 s).
  static const outGap = 0.579;

  static const badgeFill = <String, Color>{
    'top': OnboardingArtPalette.networkBlue,
    'tr': OnboardingArtPalette.networkViolet,
    'br': OnboardingArtPalette.networkBlue,
    'bl': OnboardingArtPalette.networkViolet,
    'l': OnboardingArtPalette.networkSky,
  };
  // [link colour, node dot colour] of the hub link by person art
  static const linkCol = <String, List<Color>>{
    'top': [OnboardingArtPalette.networkDeep, OnboardingArtPalette.networkDeep],
    'tr': [
      OnboardingArtPalette.networkViolet,
      OnboardingArtPalette.networkViolet,
    ],
    'br': [OnboardingArtPalette.networkSky, cyan],
    'bl': [
      OnboardingArtPalette.networkViolet,
      OnboardingArtPalette.networkViolet,
    ],
    'l': [OnboardingArtPalette.networkSky, cyan],
  };
  static const nodeFill = <String, Color>{
    'l': cyan,
    'br': cyan,
    'tr': OnboardingArtPalette.networkViolet,
    'bl': OnboardingArtPalette.networkViolet,
    'top': OnboardingArtPalette.networkDeep,
  };
  static const linkWidth = 13.0;

  late final double out0, period, introEnd;
  late final bool hasHub;
  late final Map<String, _P> icPos;
  final mids = <_Mid>[];
  final nodes = <_Node>[]; // the small people
  final e = <_Seg>[];
  final slots = <_Slot>[];
  final hubOnly = <SvgNode>[];
  late final SvgNode backG, front, flow, bgL, bgA, sceneG, hubAv;
  late final _Sfx hubSfx;
  late final List<({double t, double sc, SvgNode e})> erip;
  late final List<({double t, SvgNode e})> cps;
  var _ins = 0;

  /// The hub artwork sits a few units off the axis and is not exactly
  /// symmetric: it is moved onto the axis and rebuilt from its left half and
  /// the mirror of that half (one path, no seam), so the picture is symmetric
  /// to the pixel there too.
  double hubArtX = axis;

  void _centreHub() {
    final dx = axis - hubAv.getBBox().center.dx;
    final left = Path()..addRect(const Rect.fromLTRB(-1e5, -1e5, axis, 1e5));
    final flip = Tf.identity.translate(2 * axis).scale(-1, 1).toMatrix4();
    for (final c in hubAv.children.where((c) => c.tag == 'path')) {
      final moved = c.pathData.shift(Offset(dx, 0));
      final half = Path.combine(PathOperation.intersect, moved, left);
      c.setPath(Path.combine(PathOperation.union, half, half.transform(flip)));
    }
  }

  _P get hubC => [axis, 710];

  void _put(SvgNode n) {
    sceneG.children.remove(n);
    sceneG.children.insert(_ins++, n);
  }

  void _build() {
    hasHub = visible.contains('c');
    final cfgIc = networkArtCfg['ic']! as Map;
    icPos = {for (final k in cfgIc.keys) k as String: _pt(cfgIc[k])};
    backG = scene.byId('fxBack');
    front = scene.byId('fxFront');
    flow = scene.byId('flow');
    bgL = scene.byId('bgLinks');
    bgA = scene.byId('bgAv');
    sceneG = scene.byId('scene');
    hubAv = scene.byId('av_c');

    // the baked people, badges and links are replaced by this layout's own
    for (final k in ['top', 'tr', 'br', 'bl', 'l']) {
      scene.remove(scene.maybeId('av_$k'));
      scene.remove(scene.maybeId('ic_$k'));
      scene.remove(scene.findMasked('mk_$k'));
    }
    scene.remove(scene.findMasked('mk_ch'));
    if (!hasHub) scene.remove(hubAv);
    _ins = sceneG.children.indexOf(flow);
    if (hasHub) _centreHub();

    final left1 = [
      for (final id in kNetworkLeftTier1Persons)
        if (visible.contains(id)) id,
    ];
    for (final id in left1) {
      mids.add(_Mid(id));
    }
    // 1. avatars, 2. badges, 3. links (the baked z-order)
    for (final m in mids) {
      m.av = scene.create('g', {'opacity': 0}, sceneG);
      scene.create('use', {'href': '#s_${m.person}'}, m.av);
      _put(m.av);
    }
    for (final m in mids) {
      final b = m.badgeArt;
      final at = icPos[b]!;
      m.icWrap = scene.create('g', {}, sceneG);
      m.ic = scene.create('g', {'opacity': 0}, m.icWrap);
      scene.create('rect', {
        'x': at[0] - 80,
        'y': at[1] - 80,
        'width': 160,
        'height': 160,
        'fill': badgeFill[b]!,
        'mask': 'url(#ig_$b)',
      }, m.ic);
      _put(m.icWrap);
    }
    for (final m in mids) {
      final lc = linkCol[m.person]!;
      m.line = scene.create('line', {
        'x1': m.hubPa[0],
        'y1': m.hubPa[1],
        'x2': m.hubPb[0],
        'y2': m.hubPb[1],
        'stroke': lc[0],
        'stroke-width': linkWidth,
        'stroke-linecap': 'round',
        'stroke-dasharray':
            '${m.linkLen.toStringAsFixed(1)} ${(m.linkLen + 5).toStringAsFixed(1)}',
        'stroke-dashoffset': m.linkLen.toStringAsFixed(1),
      }, sceneG);
      _put(m.line);
      final mid = lerp2(m.hubPa, m.hubPb, 0.5);
      m.dot = scene.create('circle', {
        'cx': mid[0],
        'cy': mid[1],
        'r': 17,
        'fill': lc[1],
        'opacity': 0,
      }, sceneG);
      _put(m.dot);
    }

    // effects of the hub and of every mid person
    final fxFor = <(String, double, double, double, double, Color)>[
      if (hasHub)
        (
          'c',
          axis,
          710,
          ring['c']![2] as double,
          ring['c']![3] as double,
          ring['c']![4] as Color,
        ),
      for (final m in mids) (m.id, m.cx, m.cy, m.rx, m.ry, m.ringCol),
    ];
    for (final (id, cx, cy, rx, ry, col) in fxFor) {
      final flash = scene.create('ellipse', {
        'cx': cx,
        'cy': cy,
        'rx': rx * 1.1,
        'ry': ry * 1.6,
        'fill': col,
        'opacity': 0,
        'filter': 'url(#blur)',
      }, backG);
      final rip = <SvgNode>[
        for (var i = 0; i < 3; i++)
          scene.create('ellipse', {
            'cx': cx,
            'cy': cy,
            'rx': rx,
            'ry': ry,
            'fill': 'none',
            'stroke': i == 1 ? cyan : col,
            'stroke-width': 5,
            'opacity': 0,
          }, backG),
      ];
      final n = id == 'c' ? 14 : 9;
      final dots = <SvgNode>[
        for (var i = 0; i < n; i++)
          scene.create('circle', {
            // the hub's burst is drawn once: its second half mirrors the first
            'r': 5,
            'fill': _burstIndex(i, n, id == 'c') % 2 != 0 ? cyan : col,
            'opacity': 0,
          }, front),
      ];
      final fx = _Sfx(flash, rip, dots);
      if (id == 'c') {
        hubSfx = fx;
        hubOnly.addAll([flash, ...rip, ...dots]);
      } else {
        mids.firstWhere((m) => m.id == id).sfx = fx;
      }
    }
    if (hasHub) hubOnly.add(hubAv);
    for (final m in mids) {
      final g = scene.create('g', {
        'opacity': 0,
        'filter': 'url(#glow)',
      }, front);
      m.cmt = _Comet(
        g,
        scene.create('line', {
          'stroke': cyan,
          'stroke-width': 7,
          'stroke-linecap': 'round',
          'opacity': .9,
        }, g),
        scene.create('circle', {'r': 13, 'fill': cyan, 'opacity': .55}, g),
        scene.create('circle', {'r': 6, 'fill': white}, g),
      );
      final mid = lerp2(m.hubPa, m.hubPb, 0.5);
      m.nrip = scene.create('circle', {
        'cx': mid[0],
        'cy': mid[1],
        'r': 14,
        'fill': 'none',
        'stroke': cyan,
        'stroke-width': 4,
        'opacity': 0,
      }, front);
      m.flow = scene.create('line', {
        'x1': m.hubPa[0],
        'y1': m.hubPa[1],
        'x2': m.hubPb[0],
        'y2': m.hubPb[1],
        'stroke': white,
        'stroke-width': 3.5,
        'stroke-linecap': 'round',
        'stroke-dasharray': '0.1 34',
        'opacity': 0,
      }, flow);
      m.ifx = _Ifx(
        scene.create('circle', {
          'cx': m.badgeAt[0],
          'cy': m.badgeAt[1],
          'r': 74,
          'fill': glowCol[m.badgeArt]!,
          'opacity': 0,
          'filter': 'url(#blur)',
        }, backG),
        [
          for (var i = 0; i < 2; i++)
            scene.create('circle', {
              'cx': m.badgeAt[0],
              'cy': m.badgeAt[1],
              'r': 50,
              'fill': 'none',
              'stroke': i != 0 ? cyan : glowCol[m.badgeArt]!,
              'stroke-width': 4,
              'opacity': 0,
            }, front),
        ],
        [
          for (var i = 0; i < 7; i++)
            scene.create('path', {
              'd':
                  'M0 -9 L2.6 -2.6 L9 0 L2.6 2.6 L0 9 L-2.6 2.6 L-9 0 L-2.6 -2.6Z',
              'fill': i % 2 != 0 ? cyan : glowCol[m.badgeArt]!,
              'opacity': 0,
            }, front),
        ],
      );
      // where the comet passes the node dot (the link's middle): u of the
      // easing at f = 0.5
      m.nodeT = m.start + 0.5 * ld;
    }
    _buildKids();
    _buildElectrons();
  }

  _Node _make(_Mid m, double x, double y, String k, int ord) {
    final p = m.node;
    final nd = _Node(k, x, y, sc[1], 1, p, nodes.length + 1, ord);
    nd.t0 = base[1] + ord * 0.11;
    nd.ts = nd.t0 + 0.38;
    final rp = ring[p.k]!, rc = ring[k]!;
    nd.pa = _edge(
      [p.x, p.y],
      (rp[2] as double) * p.s,
      (rp[3] as double) * p.s,
      x,
      y,
    );
    nd.pb = _edge(
      [x, y],
      (rc[2] as double) * nd.s,
      (rc[3] as double) * nd.s,
      p.x,
      p.y,
    );
    nd.len = dist2(nd.pa, nd.pb);
    p.kids.add(nd);
    return nd;
  }

  void _buildKids() {
    var ord = 0;
    for (final m in mids) {
      final arts = kNetworkKidArtByPair[m.row]!;
      var dx = m.cx - axis, dy = m.cy - 710.0;
      final l = math.sqrt(dx * dx + dy * dy);
      dx /= l;
      dy /= l;
      for (var i = 0; i < 2; i++) {
        final off = (i != 0 ? 1 : -1) * kNetworkKidSpread;
        final c = math.cos(off), s = math.sin(off);
        var x = m.cx + (dx * c - dy * s) * kNetworkKidLength;
        var y = m.cy + (dx * s + dy * c) * kNetworkKidLength;
        if (y > 1185) {
          final sg = (x - m.cx) == 0 ? 1.0 : (x - m.cx).sign;
          x += sg * (y - 1185) * 1.4;
          y = 1185;
        }
        final kid = _make(
          m,
          clamp01(x, -385, 1925),
          clamp01(y, -190, 1235),
          arts[i],
          ord++,
        );
        kid.pid = '${m.id}-$i';
        kid.isShown = visible.contains(kid.pid);
        if (kid.isShown) nodes.add(kid);
      }
    }
    for (final n in nodes) {
      final r = ring[n.k]!;
      final col = r[4] as Color;
      final w = 6 * math.pow(n.s, 0.8);
      n.line = scene.create('line', {
        'x1': n.pa[0],
        'y1': n.pa[1],
        'x2': n.pb[0],
        'y2': n.pb[1],
        'stroke': col,
        'stroke-width': w,
        'stroke-linecap': 'round',
        'stroke-dasharray':
            '${n.len.toStringAsFixed(1)} ${(n.len + 5).toStringAsFixed(1)}',
        'stroke-dashoffset': n.len.toStringAsFixed(1),
        'opacity': opa[1],
      }, bgL);
      final m = lerp2(n.pa, n.pb, 0.5);
      n.dot = scene.create('circle', {
        'cx': m[0],
        'cy': m[1],
        'r': 16 * n.s,
        'fill': nodeFill[n.k]!,
        'opacity': 0,
      }, bgL);
      n.head = scene.create('circle', {
        'r': 6 * n.s + 2,
        'fill': cyan,
        'opacity': 0,
      }, bgL);
      n.g = scene.create('g', {'opacity': 0}, bgA);
      scene.create('use', {'href': '#s_${n.k}'}, n.g);
      n.rip = scene.create('ellipse', {
        'cx': n.x,
        'cy': n.y,
        'rx': (r[2] as double) * n.s,
        'ry': (r[3] as double) * n.s,
        'fill': 'none',
        'stroke': col,
        'stroke-width': 3,
        'opacity': 0,
      }, bgA);
      n.hasDom = true;
    }
  }

  double _pushSeg(_P a, _P b, double t0, double s) {
    final d = math.max(0.34, dist2(a, b) / 330);
    e.add(_Seg(a, b, t0, d, s));
    return t0 + d;
  }

  void _buildElectrons() {
    // the left half's electrons (the right half is the same, flipped): each
    // runs hub -> mid person -> one of its small people, one after the other
    final order = <_Mid>[];
    final targets = <_Node?>[];
    for (var i = 0; i < 2; i++) {
      for (final m in mids) {
        final kid = m.node.kids.length > i && m.node.kids[i].isShown
            ? m.node.kids[i]
            : null;
        if (kid == null && i > 0 && order.contains(m)) continue;
        order.add(m);
        targets.add(kid);
      }
    }
    const r0 = 6.9, rStep = 0.55;
    for (var ri = 0; ri < 10 && order.isNotEmpty; ri++) {
      final m = order[ri % order.length];
      final kid = targets[ri % order.length];
      var t = r0 - idleTrim + ri * rStep;
      t = _pushSeg(m.hubPa, m.hubPb, t, 1) + 0.1;
      if (kid != null) _pushSeg(kid.pa, kid.pb, t, kid.s);
    }
    var activityEnd = 0.0;
    for (final q in e) {
      activityEnd = math.max(activityEnd, q.t0 + q.d + 0.7);
    }
    var intro = 2.0;
    for (final m in mids) {
      intro = math.max(intro, m.throwT + 0.62 + 1.12);
    }
    for (final n in nodes) {
      intro = math.max(intro, n.ts + 0.6);
    }
    introEnd = intro;
    out0 = ((math.max(activityEnd, introEnd) + outGap) * 1000).round() / 1000;
    period =
        ((out0 + (NetworkIcons.htmlPeriod - _NetworkFrame.htmlOut0)) * 1000)
            .round() /
        1000;
    for (var i = 0; i < slotCount; i++) {
      final g = scene.create('g', {
        'opacity': 0,
        'filter': 'url(#glow)',
      }, front);
      final trail = [
        for (var j = 0; j < 8; j++)
          scene.create('circle', {'r': 6, 'fill': cyan}, g),
      ];
      final halo = scene.create('circle', {
        'r': 17,
        'fill': cyan,
        'opacity': .5,
      }, g);
      final hd = scene.create('circle', {
        'r': 8,
        'fill': cyan,
        'stroke': white,
        'stroke-width': 3,
      }, g);
      slots.add(_Slot(g, trail, halo, hd));
    }
    erip = [
      for (final q in e)
        (
          t: q.t0 + q.d,
          sc: q.sc,
          e: scene.create('circle', {
            'cx': q.b[0],
            'cy': q.b[1],
            'r': 10,
            'fill': 'none',
            'stroke': cyan,
            'stroke-width': 4 * math.max(.5, q.sc),
            'opacity': 0,
          }, front),
        ),
    ];
    final cT = <double>[if (hasHub) 1.0];
    for (var t = 3.8; t < out0 - 0.6; t += 2.3) {
      cT.add(t);
    }
    cps = [
      for (final t in cT)
        (
          t: t,
          e: scene.create('ellipse', {
            'cx': axis,
            'cy': 710,
            'rx': 240,
            'ry': 72,
            'fill': 'none',
            'stroke': cyan,
            'stroke-width': 5,
            'opacity': 0,
          }, backG),
        ),
    ];
    hubOnly.addAll([for (final c in cps) c.e]);
  }

  /// The index a burst dot takes its angle and colour from: on the axis the
  /// second half of the dots is the mirror of the first.
  static int _burstIndex(int i, int n, bool isOnAxis) =>
      isOnAxis && i >= n / 2 ? n - 1 - i : i;

  /// [ox], [oy]: where the artwork sits in the art data; [cx], [cy]: where the
  /// person is drawn (the offset moves the baked art).
  void _spawn(
    SvgNode el,
    _Sfx o,
    double t,
    double spawnT,
    double cx,
    double cy,
    double ox,
    double oy,
    double rx,
    double ry,
  ) {
    final u = t - spawnT;
    final p = u <= 0 ? 0.0 : _back(seg(u, 0, 0.7), 1.3);
    final q = _eo(seg(u, 0, 0.7));
    final idle = u > 0.9
        ? math.sin(t * 1.35 + cx * 0.01) * 2.4 * _eo(seg(u, 0.9, 0.8))
        : 0.0;
    el.opacity = toFixed(_eo(seg(u, 0, 0.22)), 3);
    el.transform = _tf(
      ox,
      oy,
      0.4 + 0.6 * p,
      46 * (1 - q) + idle + (cy - oy),
      0,
      cx - ox,
    );
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
      final isHub = el == hubAv;
      var a = (_burstIndex(i, n, isHub) / n) * math.pi * 2 + 0.3;
      if (isHub && i >= n / 2) a = math.pi - a;
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
    final o = seg(t, out0, _NetworkFrame.outD);
    sceneG.opacity = toFixed(1 - _eo(o), 3);
    sceneG.transform = _tf(axis, 512, 1 - 0.03 * _eo(o));

    if (hasHub) {
      _spawn(
        hubAv,
        hubSfx,
        t,
        0,
        axis,
        710,
        hubArtX,
        710,
        ring['c']![2] as double,
        ring['c']![3] as double,
      );
    }
    for (final m in mids) {
      _spawn(
        m.av,
        m.sfx,
        t,
        m.spawnT,
        m.cx,
        m.cy,
        m.artC[0],
        m.artC[1],
        m.rx,
        m.ry,
      );

      final s0 = m.start;
      final p = _eio(seg(t, s0, ld));
      final c = m.cmt;
      m.line.dashOffset = toFixed(m.linkLen * (1 - p), 2);
      final vis = t > s0 && t < s0 + ld + 0.12;
      c.g.opacity = vis ? toFixed(1 - seg(t, s0 + ld, 0.12), 3) : 0;
      if (vis) {
        final h = lerp2(m.hubPa, m.hubPb, p);
        final tl = lerp2(m.hubPa, m.hubPb, math.max(0.0, p - 0.22));
        c.head.cx = h[0];
        c.head.cy = h[1];
        c.halo.cx = h[0];
        c.halo.cy = h[1];
        c.streak.x1 = tl[0];
        c.streak.y1 = tl[1];
        c.streak.x2 = h[0];
        c.streak.y2 = h[1];
      }
      final v = seg(t, m.nodeT, 0.7);
      m.nrip.opacity = toFixed(t > m.nodeT && v < 1 ? 0.85 * (1 - v) : 0, 3);
      m.nrip.r = toFixed(12 + 40 * _eo(v), 1);
      final dd = _eo(seg(t, m.nodeT - 0.05, 0.2));
      m.dot.opacity = toFixed(dd, 3);
      m.dot.transform = _tf(m.dot.cx, m.dot.cy, 0.4 + 0.6 * dd);
      final on = _eo(seg(t, s0 + ld + 0.6, 0.8)) * (1 - _eo(o));
      m.flow.opacity = toFixed(0.8 * on, 3);
      m.flow.dashOffset = toFixed(-t * 26, 1);

      // the badge
      final el = m.ic, f = m.ifx;
      final bx = m.badgeAt[0], by = m.badgeAt[1];
      final ob = icPos[m.badgeArt]!;
      final u = t - m.throwT;
      final isOn = u > 0;
      final bv = seg(u, 0, 0.8);
      final ev = _eo(bv);
      final dx = (m.badgeFrom[0] - bx) * (1 - ev);
      final dy = (m.badgeFrom[1] - by) * (1 - ev) - 70 * math.sin(math.pi * ev);
      final fl = isOn
          ? math.sin(t * 1.6 + bx * 0.02) * 3 * _eo(seg(u, 0.9, 0.7))
          : 0.0;
      final scl =
          (0.15 + 0.85 * (isOn ? _back(bv, 1.6) : 0)) *
          (1 + 0.05 * bump(seg(u, 0.7, 0.55)));
      el.opacity = toFixed(_eo(seg(u, 0, 0.15)), 3);
      el.transform = _tf(
        ob[0],
        ob[1],
        scl,
        dy + fl + (by - ob[1]),
        -22 * (1 - ev),
        dx + (bx - ob[0]),
      );
      final l = t - (m.throwT + 0.62);
      final rest =
          0.22 *
          _eo(seg(l, 0.2, 0.8)) *
          (0.82 + 0.18 * math.sin(t * 1.9 + by * 0.01));
      f.glow.opacity = l > 0
          ? toFixed(
              math.min(1.0, 0.42 * bump(seg(l, 0, 1.0)) + rest) * (1 - _eo(o)),
              3,
            )
          : 0;
      f.glow.transform = _tf(bx, by, 0.6 + 0.6 * _eo(seg(l, 0, 0.9)), fl);
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
            .translate(
              toFixed(bx + math.cos(a) * d, 1),
              toFixed(by + math.sin(a) * d * 0.9, 1),
            )
            .rotate(w * 70)
            .scale(toFixed(1.8 * (1 - w) + 0.1, 2));
      }
    }

    for (final n in nodes) {
      final lp = _eio(seg(t, n.t0, 0.5));
      final u = t - n.ts;
      final rr = ring[n.k]!;
      final rcx = rr[0] as double, rcy = rr[1] as double;
      n.line.dashOffset = toFixed(n.len * (1 - lp), 1);
      n.line.opacity = toFixed(opa[1] * (1 - _eo(o)), 3);
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
      n.dot.opacity = toFixed(dd * opa[1] * (1 - _eo(o)), 3);
      n.dot.transform = _tf(n.dot.cx, n.dot.cy, 0.4 + 0.6 * dd);
      final idle = u > 0.8
          ? math.sin(t * 1.2 + n.id * 0.9) * 2 * n.s * _eo(seg(u, 0.8, 0.8))
          : 0.0;
      final sc2 = n.s * (0.4 + 0.6 * (u > 0 ? dp : 0));
      n.g.transform = Tf.identity
          .translate(n.x, n.y + 40 * n.s * (1 - dq) + idle)
          .scale(toFixed(sc2, 3))
          .translate(-rcx, -rcy);
      n.g.opacity = toFixed(opa[1] * _eo(seg(u, 0, 0.2)) * (1 - _eo(o)), 3);
      final rv = seg(u, 0.03, 0.9);
      n.rip.opacity = toFixed(u > 0 && rv < 1 ? 0.6 * (1 - rv) : 0, 3);
      n.rip.transform = _tf(n.x, n.y, 0.6 + 1.0 * _eo(rv));
    }

    var si = 0;
    for (final q in e) {
      if (t < q.t0 || t > q.t0 + q.d || si >= slotCount) continue;
      final s = slots[si++];
      final u = (t - q.t0) / q.d;
      final f = math.min(
        _eo(clamp01(u / 0.15)),
        1 - _eo(clamp01((u - 0.88) / 0.12)),
      );
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
        final w = math.max(
          0.0,
          u - (j + 1) * 0.035 * (dist2(q.a, q.b) > 150 ? 1 : 2),
        );
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
      c.e.transform = _tf(axis, 710, 1 + 0.35 * _eo(v));
    }
  }

  /// Hides the hub-owned nodes while the mirrored half is drawn (the hub is on
  /// the axis and drawn once).
  void setMirrored(bool isMirrored) {
    for (final n in hubOnly) {
      n.display = !isMirrored;
    }
    if (kNetworkFlipBadgeGlyphs) return;
    // keep the badge glyphs (tick, chat tail) reading the right way round:
    // flip each badge about its own centre, the canvas flip then undoes it
    for (final m in mids) {
      m.icWrap.transform = isMirrored
          ? Tf.identity
                .translate(m.badgeAt[0])
                .scale(-1, 1)
                .translate(-m.badgeAt[0])
          : null;
    }
  }
}

/// One mid person of the left half.
class _Mid {
  _Mid(this.id) {
    row = kNetworkMidRow[id]!;
    person = kNetworkPersonByPair[row]!;
    badgeArt = kNetworkBadgeArt[kNetworkBadgeByPair[row]!]!;
    cx = _SymFrame.axis - kNetworkRowDx[row]!;
    cy = kNetworkRowY[row]!;
    final r = _SymFrame.ring[person]!;
    artC = [r[0] as double, r[1] as double];
    rx = r[2] as double;
    ry = r[3] as double;
    ringCol = r[4] as Color;
    node = _Node(person, cx, cy, 1, 0, null, 0, 0)..pid = id;
    final hub = [_SymFrame.axis, 710.0];
    final hr = _SymFrame.ring['c']!;
    hubPa = _edge(hub, hr[2] as double, hr[3] as double, cx, cy);
    hubPb = _edge([cx, cy], rx, ry, hub[0], hub[1]);
    linkLen = dist2(hubPa, hubPb);
    // the badge sits on the outer (left) side, as far from the person as its
    // own art's badge is from its own person
    final ib = _symIc[badgeArt]!;
    final rb = _SymFrame.ring[badgeArt]!;
    final hb = _SymFrame.head[badgeArt]!;
    badgeAt = [
      cx - (ib[0] - (rb[0] as double)),
      cy + (ib[1] - (rb[1] as double)),
    ];
    badgeFrom = [
      cx - (hb[0] - (rb[0] as double)),
      cy + (hb[1] - (rb[1] as double)),
    ];
    start = kNetworkRowStart[row]!;
    spawnT = start + _SymFrame.ld - 0.15;
    throwT = spawnT + 0.35;
  }

  final String id;
  late final String row, person, badgeArt;
  late final double cx, cy, rx, ry, start, spawnT, throwT, linkLen;
  late final _P artC, hubPa, hubPb, badgeAt, badgeFrom;
  late final Color ringCol;
  late final _Node node;
  double nodeT = 0;
  late SvgNode av, icWrap, ic, line, dot, nrip, flow;
  late _Sfx sfx;
  late _Comet cmt;
  late _Ifx ifx;
}

/// The resting badge positions of the art data (`ic` in networkArtCfg).
final Map<String, _P> _symIc = {
  for (final en in (networkArtCfg['ic']! as Map).entries)
    en.key as String: _pt(en.value),
};
