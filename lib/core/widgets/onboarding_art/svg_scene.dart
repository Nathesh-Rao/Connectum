import 'dart:math' as math;
import 'dart:ui';

import 'svg_path_parser.dart';

/// One element of the generated art data (see tool/onboarding_anim/extract_art.py).
class ArtEl {
  const ArtEl(this.tag, this.attrs, [this.children = const []]);

  final String tag;
  final Map<String, String> attrs;
  final List<ArtEl> children;
}

class SvgFilter {
  SvgFilter(this.sigma, {required this.isGlow});

  final double sigma;

  /// feMerge of the blur and the source graphic.
  final bool isGlow;
}

class SvgClip {
  final List<SvgNode> shapes = [];
  Path? _union;
}

class SvgMask {
  SvgMask(this.region);

  final Rect region;
  final List<SvgNode> children = [];

  // set on first use: an all-white fills mask is the same as a clip
  bool? _isClip;
  bool _isStatic = false;
  Path? _clipPath;
}

/// A mutable SVG element: the scripts change its attributes every frame.
class SvgNode {
  SvgNode(this.tag);

  final String tag;
  String? id;
  List<String> classes = const [];
  SvgNode? parent;
  final List<SvgNode> children = [];
  final Map<String, String> data = {};

  // presentation (null = inherited)
  Color? fill;
  Color? stroke;
  double? strokeWidth;
  StrokeCap? cap;
  StrokeJoin? join;
  double strokeOpacity = 1;
  double opacity = 1;
  bool display = true;
  bool visible = true;
  Tf? transform;
  List<double>? dash;
  double dashOffset = 0;
  double? pathLength;
  SvgClip? clip;
  SvgMask? mask;
  SvgFilter? filter;

  // geometry
  String? d;
  double x = 0, y = 0, width = 0, height = 0, rx = 0, ry = 0;
  double cx = 0, cy = 0, r = 0;
  double x1 = 0, y1 = 0, x2 = 0, y2 = 0;
  SvgNode? ref;

  ParsedPath? _parsed;

  ParsedPath get parsed => _parsed ??= parseSvgPath(d ?? '');

  /// Replaces the geometry of a path element with [p] (no path data string).
  void setPath(Path p) => _parsed = ParsedPath(p, p.getBounds());

  /// The path data as a Path (path elements only).
  Path get pathData => parsed.path;

  /// Geometry of any shape as a Path (for clips, bounds, dashes).
  Path shapePath() {
    switch (tag) {
      case 'path':
        return parsed.path;
      case 'rect':
        final rr = RRect.fromRectXY(
          Rect.fromLTWH(x, y, width, height),
          rx > 0 ? rx : ry,
          ry > 0 ? ry : rx,
        );
        return Path()..addRRect(rr);
      case 'circle':
        return Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      case 'ellipse':
        return Path()..addOval(Rect.fromCenter(
          center: Offset(cx, cy),
          width: rx * 2,
          height: ry * 2,
        ));
      case 'line':
        return Path()
          ..moveTo(x1, y1)
          ..lineTo(x2, y2);
      case 'use':
        return ref?.shapePath() ?? Path();
    }
    return Path();
  }

  /// `getBBox()`: geometry only, no stroke, in this element's own user space.
  Rect getBBox() {
    switch (tag) {
      case 'path':
        return parsed.bounds;
      case 'rect':
        return Rect.fromLTWH(x, y, width, height);
      case 'circle':
        return Rect.fromCircle(center: Offset(cx, cy), radius: r);
      case 'ellipse':
        return Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2);
      case 'line':
        return Rect.fromPoints(Offset(x1, y1), Offset(x2, y2));
      case 'use':
        final b = ref?.getBBox() ?? Rect.zero;
        return ref?.transform?.mapRect(b) ?? b;
    }
    Rect? out;
    for (final c in children) {
      if (c.tag == 'defs') continue;
      var b = c.getBBox();
      if (c.transform != null) b = c.transform!.mapRect(b);
      out = out == null ? b : out.expandToInclude(b);
    }
    return out ?? Rect.zero;
  }

  void add(SvgNode c) {
    c.parent = this;
    children.add(c);
  }
}

const _black = Color.fromARGB(255, 0, 0, 0);
const _white = Color.fromARGB(255, 255, 255, 255);
const _clear = Color.fromARGB(0, 0, 0, 0);

final _colorRe = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$');

/// Parses an authored colour (`#RGB`, `#RRGGBB`, `white`, `none`).
Color? parseSvgColor(String v) {
  final s = v.trim();
  if (s == 'none') return _clear;
  if (s.toLowerCase() == 'white') return _white;
  final m = _colorRe.firstMatch(s);
  if (m == null) return null;
  var h = m[1]!;
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  return Color(int.parse('FF$h', radix: 16));
}

String _urlId(String v) => RegExp(r'url\(#([^)]+)\)').firstMatch(v)![1]!;

/// A scene built from art data. Elements with ids and classes can be looked up
/// and mutated; [create] adds elements the way the scripts' `mk()` does.
class SvgScene {
  SvgScene._(this.viewBox, this.remap);

  final Rect viewBox;
  final Color Function(Color) remap;
  final root = SvgNode('svg');
  final Map<String, SvgNode> _byId = {};
  final Map<String, SvgClip> _clips = {};
  final Map<String, SvgMask> _masks = {};
  final Map<String, SvgFilter> _filters = {};
  final List<void Function()> _pending = [];

  /// Elements added with [create] by tag (the script-built ones).
  final createdByTag = <String, int>{};

  static SvgScene fromArt(ArtEl art, {Color Function(Color)? remap}) {
    final vb = art.attrs['viewBox']!.split(RegExp(r'\s+')).map(double.parse).toList();
    final s = SvgScene._(Rect.fromLTWH(vb[0], vb[1], vb[2], vb[3]), remap ?? (c) => c);
    for (final c in art.children) {
      s._build(c, s.root);
    }
    for (final f in s._pending) {
      f();
    }
    s._pending.clear();
    return s;
  }

  /// The element that uses the mask [id] (the masked link graphics).
  SvgNode? findMasked(String id) {
    final m = _masks[id];
    if (m == null) return null;
    SvgNode? hit;
    void walk(SvgNode n) {
      if (n.mask == m) hit = n;
      n.children.forEach(walk);
    }

    walk(root);
    return hit;
  }

  /// Removes [n] (and everything under it) from the drawing.
  void remove(SvgNode? n) {
    n?.parent?.children.remove(n);
    n?.parent = null;
  }

  SvgNode byId(String id) => _byId[id] ?? (throw StateError('no element #$id'));

  SvgNode? maybeId(String id) => _byId[id];

  List<SvgNode> byClass(String cls) {
    final out = <SvgNode>[];
    void walk(SvgNode n) {
      if (n.classes.contains(cls)) out.add(n);
      n.children.forEach(walk);
    }

    walk(root);
    for (final m in _masks.values) {
      m.children.forEach(walk);
    }
    return out;
  }

  /// `mk(tag, attrs, parent)` of the scripts.
  SvgNode create(String tag, Map<String, Object> attrs, SvgNode parent) {
    final n = SvgNode(tag);
    createdByTag[tag] = (createdByTag[tag] ?? 0) + 1;
    attrs.forEach((k, v) {
      if (v is Color) {
        final c = remap(v);
        if (k == 'fill') n.fill = c;
        if (k == 'stroke') n.stroke = c;
      } else {
        _set(n, k, '$v');
      }
    });
    parent.add(n);
    for (final f in _pending) {
      f();
    }
    _pending.clear();
    return n;
  }

  Color color(String v) => remap(parseSvgColor(v)!);

  void _build(ArtEl el, SvgNode parent) {
    switch (el.tag) {
      case 'defs':
        // definitions are only reachable through use / clip / mask references
        final holder = SvgNode('g');
        for (final c in el.children) {
          _build(c, holder);
        }
        return;
      case 'clipPath':
        final clip = SvgClip();
        for (final c in el.children) {
          final n = SvgNode(c.tag);
          c.attrs.forEach((k, v) => _set(n, k, v));
          clip.shapes.add(n);
        }
        _clips[el.attrs['id']!] = clip;
        return;
      case 'mask':
        final a = el.attrs;
        final m = SvgMask(Rect.fromLTWH(
          double.parse(a['x'] ?? '0'),
          double.parse(a['y'] ?? '0'),
          double.parse(a['width'] ?? '0'),
          double.parse(a['height'] ?? '0'),
        ));
        final holder = SvgNode('g');
        for (final c in el.children) {
          _build(c, holder);
        }
        for (final c in holder.children) {
          m.children.add(c);
        }
        _masks[a['id']!] = m;
        return;
      case 'filter':
        final blur = el.children.firstWhere((c) => c.tag == 'feGaussianBlur');
        _filters[el.attrs['id']!] = SvgFilter(
          double.parse(blur.attrs['stdDeviation']!),
          isGlow: el.children.any((c) => c.tag == 'feMerge'),
        );
        return;
    }
    final n = SvgNode(el.tag);
    el.attrs.forEach((k, v) => _set(n, k, v));
    parent.add(n);
    for (final c in el.children) {
      _build(c, n);
    }
  }

  void _set(SvgNode n, String k, String v) {
    double num(String s) => double.parse(s);
    switch (k) {
      case 'id':
        n.id = v;
        _byId[v] = n;
      case 'class':
        n.classes = v.split(RegExp(r'\s+'));
      case 'transform':
        n.transform = Tf.parse(v);
      case 'opacity':
        n.opacity = num(v);
      case 'stroke-opacity':
        n.strokeOpacity = num(v);
      case 'fill':
        n.fill = color(v);
      case 'stroke':
        n.stroke = color(v);
      case 'stroke-width':
        n.strokeWidth = num(v);
      case 'stroke-linecap':
        n.cap = switch (v) {
          'round' => StrokeCap.round,
          'square' => StrokeCap.square,
          _ => StrokeCap.butt,
        };
      case 'stroke-linejoin':
        n.join = switch (v) {
          'round' => StrokeJoin.round,
          'bevel' => StrokeJoin.bevel,
          _ => StrokeJoin.miter,
        };
      case 'stroke-dasharray':
        n.dash = v.split(RegExp(r'[\s,]+')).map(num).toList();
      case 'stroke-dashoffset':
        n.dashOffset = num(v);
      case 'pathLength':
        n.pathLength = num(v);
      case 'display':
        n.display = v != 'none';
      case 'visibility':
        n.visible = v != 'hidden';
      case 'd':
        n.d = v;
        n._parsed = null;
      case 'x':
        n.x = num(v);
      case 'y':
        n.y = num(v);
      case 'width':
        n.width = num(v);
      case 'height':
        n.height = num(v);
      case 'rx':
        n.rx = num(v);
      case 'ry':
        n.ry = num(v);
      case 'cx':
        n.cx = num(v);
      case 'cy':
        n.cy = num(v);
      case 'r':
        n.r = num(v);
      case 'x1':
        n.x1 = num(v);
      case 'y1':
        n.y1 = num(v);
      case 'x2':
        n.x2 = num(v);
      case 'y2':
        n.y2 = num(v);
      case 'href':
        final id = v.substring(1);
        _pending.add(() => n.ref = _byId[id]);
      case 'clip-path':
        final id = _urlId(v);
        _pending.add(() => n.clip = _clips[id]);
      case 'mask':
        final id = _urlId(v);
        _pending.add(() => n.mask = _masks[id]);
      case 'filter':
        final id = _urlId(v);
        _pending.add(() => n.filter = _filters[id]);
      default:
        if (k.startsWith('data-')) n.data[k.substring(5)] = v;
    }
  }
}

/// One painted leaf element and where it lands in scene units.
class DrawnRect {
  const DrawnRect(this.node, this.label, this.rect, [this.via = const []]);

  final SvgNode node;

  /// Every element visited from the root down to [node] (use elements
  /// included), so a test can tell which person group a leaf belongs to.
  final List<SvgNode> via;

  /// The element ids on the way down, joined with `>` (for error messages).
  final String label;
  final Rect rect;
}

class _Style {
  const _Style(this.fill, this.stroke, this.strokeWidth, this.cap, this.join);

  static const root = _Style(_black, null, 1, StrokeCap.butt, StrokeJoin.miter);

  final Color? fill;
  final Color? stroke;
  final double strokeWidth;
  final StrokeCap cap;
  final StrokeJoin join;

  _Style apply(SvgNode n) {
    if (n.fill == null &&
        n.stroke == null &&
        n.strokeWidth == null &&
        n.cap == null &&
        n.join == null) {
      return this;
    }
    return _Style(
      n.fill ?? fill,
      n.stroke ?? stroke,
      n.strokeWidth ?? strokeWidth,
      n.cap ?? cap,
      n.join ?? join,
    );
  }
}

/// Draws an [SvgScene] with the browser's effect order: transform, filter,
/// clip, mask, opacity. Group opacity, masks and filters use saveLayer; plain
/// fills and strokes fold opacity into their alpha.
class SvgRenderer {
  SvgRenderer(this.scene);

  final SvgScene scene;

  /// saveLayer calls of the last [paint] (a frame-cost measure).
  int layerCount = 0;
  final _plainLayer = Paint();
  final _blurs = <double, ImageFilter>{};
  final _maskBase = Paint()..color = _black;
  final _fillPaint = Paint()..style = PaintingStyle.fill..isAntiAlias = true;
  final _strokePaint = Paint()..style = PaintingStyle.stroke..isAntiAlias = true;
  final _layerPaint = Paint();
  static final _lumaFilter = ColorFilter.matrix(<double>[
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
  ]);

  void _layer(Canvas canvas, Rect? bounds, Paint paint) {
    layerCount++;
    canvas.saveLayer(bounds, paint);
  }

  void paint(Canvas canvas) {
    layerCount = 0;
    for (final c in scene.root.children) {
      _node(canvas, c, _Style.root);
    }
  }

  static bool _isShape(String tag) =>
      tag == 'path' ||
      tag == 'rect' ||
      tag == 'circle' ||
      tag == 'ellipse' ||
      tag == 'line';

  void _node(Canvas canvas, SvgNode n, _Style inherited) {
    if (!n.display || !n.visible || n.opacity <= 0) return;
    final st = inherited.apply(n);
    final isShape = _isShape(n.tag);
    final mask = n.mask;
    final maskClip = mask == null ? null : _maskClip(mask);
    final hasMask = mask != null && maskClip == null;
    final plain = isShape && n.filter == null && !hasMask;
    final hasFill = n.tag != 'line' && st.fill != null && st.fill!.a > 0;
    final hasStroke = st.stroke != null && st.stroke!.a > 0 && st.strokeWidth > 0;
    final foldOpacity = plain && n.opacity < 1 && !(hasFill && hasStroke);
    // a blur-only filter folds the opacity into its own layer
    final opacityInFilter =
        n.filter != null && !n.filter!.isGlow && !hasMask;
    final needsLayer = n.opacity < 1 && !foldOpacity && !opacityInFilter;
    final bare = n.transform == null &&
        n.clip == null &&
        mask == null &&
        n.filter == null &&
        !needsLayer;
    if (bare) {
      _content(canvas, n, st, foldOpacity ? n.opacity : 1);
      return;
    }
    canvas.save();
    if (n.transform != null) canvas.transform(n.transform!.toMatrix4());
    final clip = n.clip;
    if (clip != null) _applyClip(canvas, clip);
    if (maskClip != null) {
      canvas.clipRect(mask!.region);
      canvas.clipPath(maskClip);
    }
    final bounds = (needsLayer || hasMask || n.filter != null)
        ? _layerBounds(n)
        : null;
    if ((needsLayer || hasMask || n.filter != null) && bounds == null) {
      canvas.restore();
      return;
    }
    if (needsLayer) {
      _layerPaint
        ..color = Color.fromRGBO(0, 0, 0, n.opacity)
        ..blendMode = BlendMode.srcOver
        ..colorFilter = null
        ..imageFilter = null;
      _layer(canvas, bounds, _layerPaint);
    }
    _masked(canvas, n, st, bounds, foldOpacity ? n.opacity : 1, hasMask);
    if (needsLayer) canvas.restore();
    canvas.restore();
  }

  void _masked(
    Canvas canvas,
    SvgNode n,
    _Style st,
    Rect? bounds,
    double alpha,
    bool hasMask,
  ) {
    final mask = n.mask;
    if (!hasMask || mask == null) {
      _filtered(canvas, n, st, bounds, alpha, false);
      return;
    }
    _layer(canvas, bounds, _plainLayer);
    _filtered(canvas, n, st, bounds, alpha, true);
    _layerPaint
      ..color = _black
      ..blendMode = BlendMode.dstIn
      ..colorFilter = _lumaFilter
      ..imageFilter = null;
    _layer(canvas, bounds, _layerPaint);
    canvas.drawRect(bounds!, _maskBase);
    for (final c in mask.children) {
      _node(canvas, c, _Style.root);
    }
    canvas.restore();
    canvas.restore();
  }

  void _filtered(
    Canvas canvas,
    SvgNode n,
    _Style st,
    Rect? bounds,
    double alpha,
    bool hasMask,
  ) {
    final f = n.filter;
    if (f == null) {
      _content(canvas, n, st, alpha);
      return;
    }
    final m = canvas.getTransform();
    final scale = math.sqrt(m[0] * m[0] + m[1] * m[1]);
    final s = f.sigma * scale;
    final fade = f.isGlow || hasMask ? 1.0 : n.opacity;
    _layerPaint
      ..color = Color.fromRGBO(0, 0, 0, fade)
      ..blendMode = BlendMode.srcOver
      ..colorFilter = null
      ..imageFilter = _blurs.putIfAbsent(
        s,
        () => ImageFilter.blur(sigmaX: s, sigmaY: s, tileMode: TileMode.decal),
      );
    _layer(canvas, bounds, _layerPaint);
    _content(canvas, n, st, alpha);
    canvas.restore();
    if (f.isGlow) _content(canvas, n, st, alpha);
  }

  void _content(Canvas canvas, SvgNode n, _Style st, double alpha) {
    switch (n.tag) {
      case 'g':
      case 'svg':
        for (final c in n.children) {
          _node(canvas, c, st);
        }
      case 'use':
        final ref = n.ref;
        if (ref != null) _node(canvas, ref, st);
      case 'defs':
      case 'clipPath':
      case 'mask':
      case 'filter':
        break;
      default:
        _shape(canvas, n, st, alpha);
    }
  }

  void _shape(Canvas canvas, SvgNode n, _Style st, double alpha) {
    final fill = st.fill;
    if (fill != null && fill.a > 0 && n.tag != 'line') {
      _fillPaint.color = fill.withValues(alpha: fill.a * alpha);
      switch (n.tag) {
        case 'path':
          canvas.drawPath(n.parsed.path, _fillPaint);
        case 'rect':
          if (n.rx > 0 || n.ry > 0) {
            canvas.drawRRect(
              RRect.fromRectXY(
                Rect.fromLTWH(n.x, n.y, n.width, n.height),
                n.rx > 0 ? n.rx : n.ry,
                n.ry > 0 ? n.ry : n.rx,
              ),
              _fillPaint,
            );
          } else {
            canvas.drawRect(Rect.fromLTWH(n.x, n.y, n.width, n.height), _fillPaint);
          }
        case 'circle':
          canvas.drawCircle(Offset(n.cx, n.cy), n.r, _fillPaint);
        case 'ellipse':
          canvas.drawOval(
            Rect.fromCenter(center: Offset(n.cx, n.cy), width: n.rx * 2, height: n.ry * 2),
            _fillPaint,
          );
      }
    }
    final stroke = st.stroke;
    if (stroke != null && stroke.a > 0 && st.strokeWidth > 0) {
      _strokePaint
        ..color = stroke.withValues(alpha: stroke.a * n.strokeOpacity * alpha)
        ..strokeWidth = st.strokeWidth
        ..strokeCap = st.cap
        ..strokeJoin = st.join;
      _stroke(canvas, n, st, _strokePaint);
    }
  }

  void _stroke(Canvas canvas, SvgNode n, _Style st, Paint p) {
    final dash = n.dash;
    if (dash == null || dash.length < 2 || dash[0] + dash[1] <= 0) {
      switch (n.tag) {
        case 'line':
          canvas.drawLine(Offset(n.x1, n.y1), Offset(n.x2, n.y2), p);
        case 'circle':
          canvas.drawCircle(Offset(n.cx, n.cy), n.r, p);
        case 'ellipse':
          canvas.drawOval(
            Rect.fromCenter(center: Offset(n.cx, n.cy), width: n.rx * 2, height: n.ry * 2),
            p,
          );
        default:
          canvas.drawPath(n.shapePath(), p);
      }
      return;
    }
    final period = dash[0] + dash[1];
    final isDots = dash[0] <= 0.5 && st.cap == StrokeCap.round;
    if (n.tag == 'line' && !isDots) {
      final dx = n.x2 - n.x1, dy = n.y2 - n.y1;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len == 0) return;
      var s0 = -(n.dashOffset % period);
      if (s0 > 0) s0 -= period;
      for (; s0 < len; s0 += period) {
        final a = math.max(s0, 0.0), b = math.min(s0 + dash[0], len);
        if (b > a) {
          canvas.drawLine(
            Offset(n.x1 + dx / len * a, n.y1 + dy / len * a),
            Offset(n.x1 + dx / len * b, n.y1 + dy / len * b),
            p,
          );
        }
      }
      return;
    }
    if (isDots && (n.tag == 'circle' || n.tag == 'line')) {
      final pts = <Offset>[];
      final off = n.dashOffset;
      var k = (off / period).ceil();
      if (n.tag == 'circle') {
        final len = 2 * math.pi * n.r;
        for (;; k++) {
          final s = k * period - off;
          if (s >= len) break;
          final a = s / n.r;
          pts.add(Offset(n.cx + n.r * math.cos(a), n.cy + n.r * math.sin(a)));
        }
      } else {
        final dx = n.x2 - n.x1, dy = n.y2 - n.y1;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len == 0) return;
        for (;; k++) {
          final s = k * period - off;
          if (s >= len) break;
          pts.add(Offset(n.x1 + dx / len * s, n.y1 + dy / len * s));
        }
      }
      canvas.drawPoints(PointMode.points, pts, p);
      return;
    }
    final out = Path();
    for (final metric in n.shapePath().computeMetrics()) {
      final scale = n.pathLength != null ? metric.length / n.pathLength! : 1.0;
      final d0 = dash[0] * scale, per = period * scale;
      final off = n.dashOffset * scale;
      var s = -(off % per);
      if (s > 0) s -= per;
      for (; s < metric.length; s += per) {
        final a = math.max(s, 0.0), b = math.min(s + d0, metric.length);
        if (b > a) {
          out.addPath(metric.extractPath(a, b), Offset.zero);
        } else if (d0 == 0 && s >= 0) {
          out.addPath(metric.extractPath(s, s + 0.01), Offset.zero);
        }
      }
    }
    canvas.drawPath(out, p);
  }

  /// Every visible leaf element with its bounds in scene units: stroke width,
  /// blur radius, clip and mask limits and all transforms included; elements
  /// that are hidden or (almost) transparent are left out.
  List<DrawnRect> drawnRects({double minOpacity = 0.02}) => [
    for (final c in scene.root.children)
      ..._drawn(c, '', _Style.root, minOpacity, const []),
  ];

  List<DrawnRect> _drawn(
    SvgNode n,
    String ctx,
    _Style inherited,
    double minOpacity,
    List<SvgNode> chain,
  ) {
    if (!n.display || !n.visible || n.opacity < minOpacity) return const [];
    final st = inherited.apply(n);
    // the ids on the way down, e.g. `scene>av_top>s_top`
    final label = n.id == null ? ctx : (ctx.isEmpty ? n.id! : '$ctx>${n.id}');
    final via = [...chain, n];
    var items = <DrawnRect>[];
    switch (n.tag) {
      case 'g':
      case 'svg':
        for (final c in n.children) {
          items.addAll(_drawn(c, label, st, minOpacity, via));
        }
      case 'use':
        if (n.ref != null) items = _drawn(n.ref!, label, st, minOpacity, via);
      case 'defs':
      case 'clipPath':
      case 'mask':
      case 'filter':
        return const [];
      default:
        final hasStroke = st.stroke != null && st.stroke!.a > 0 && st.strokeWidth > 0;
        var r = n.getBBox();
        if (hasStroke) r = r.inflate(st.strokeWidth / 2);
        items.add(DrawnRect(n, label, r, via));
    }
    if (items.isEmpty) return items;
    if (n.filter != null) {
      final grow = n.filter!.sigma * 3;
      items = [for (final d in items) DrawnRect(d.node, d.label, d.rect.inflate(grow), d.via)];
    }
    final clip = n.clip;
    if (clip != null) {
      final cb = _clipBounds(clip);
      items = [
        for (final d in items)
          if (d.rect.overlaps(cb) && !d.rect.intersect(cb).isEmpty)
            DrawnRect(d.node, d.label, d.rect.intersect(cb), d.via),
      ];
    }
    final mask = n.mask;
    if (mask != null) {
      Rect? mb;
      for (final c in mask.children) {
        for (final d in _drawn(c, label, _Style.root, 0, via)) {
          mb = mb == null ? d.rect : mb.expandToInclude(d.rect);
        }
      }
      if (mb == null) return const [];
      final box = mb.intersect(mask.region);
      items = [
        for (final d in items)
          if (d.rect.overlaps(box) && !d.rect.intersect(box).isEmpty)
            DrawnRect(d.node, d.label, d.rect.intersect(box), d.via),
      ];
    }
    final tf = n.transform;
    if (tf != null) {
      items = [for (final d in items) DrawnRect(d.node, d.label, tf.mapRect(d.rect), d.via)];
    }
    return items;
  }

  Rect _clipBounds(SvgClip clip) {
    if (clip.shapes.length == 1 && clip.shapes.first.tag == 'rect') {
      final r = clip.shapes.first;
      return Rect.fromLTWH(r.x, r.y, r.width, r.height);
    }
    Path? path;
    for (final sh in clip.shapes) {
      final sp = sh.shapePath();
      path = path == null ? sp : Path.combine(PathOperation.union, path, sp);
    }
    return (path ?? Path()).getBounds();
  }

  /// The clip equal to [m] when every child is an opaque white fill, else null.
  Path? _maskClip(SvgMask m) {
    m._isClip ??= m.children.isNotEmpty &&
        m.children.every(
          (c) =>
              (c.tag == 'path' ||
                  c.tag == 'rect' ||
                  c.tag == 'circle' ||
                  c.tag == 'ellipse') &&
              c.fill != null &&
              c.fill!.a >= 0.999 &&
              c.fill!.r >= 0.999 &&
              c.fill!.g >= 0.999 &&
              c.fill!.b >= 0.999 &&
              (c.stroke == null || c.stroke!.a == 0) &&
              c.opacity == 1 &&
              c.transform == null &&
              c.mask == null &&
              c.clip == null &&
              c.filter == null,
        );
    if (m._isClip != true) return null;
    m._isStatic = m.children.every((c) => c.id == null);
    if (m._isStatic && m._clipPath != null) return m._clipPath;
    Path? path;
    for (final c in m.children) {
      final sp = c.shapePath();
      path = path == null ? sp : Path.combine(PathOperation.union, path, sp);
    }
    if (m._isStatic) m._clipPath = path;
    return path;
  }

  void _applyClip(Canvas canvas, SvgClip clip) {
    if (clip.shapes.length == 1 && clip.shapes.first.tag == 'rect') {
      final r = clip.shapes.first;
      canvas.clipRect(Rect.fromLTWH(r.x, r.y, r.width, r.height));
      return;
    }
    var path = clip._union;
    if (path == null) {
      for (final s in clip.shapes) {
        final sp = s.shapePath();
        path = path == null ? sp : Path.combine(PathOperation.union, path, sp);
      }
      path ??= Path();
      if (clip.shapes.every((s) => s.tag == 'use')) clip._union = path;
    }
    canvas.clipPath(path);
  }

  /// Local bounds (including stroke and blur) used to size layers.
  Rect? _layerBounds(SvgNode n) {
    // local space: the node's own transform is already on the canvas
    var b = _bounds(n, includeOwn: false);
    if (b == null) return null;
    if (n.filter != null) b = b.inflate(n.filter!.sigma * 3 + 2);
    final mask = n.mask;
    if (mask != null) {
      Rect? mb;
      for (final c in mask.children) {
        final r = _bounds(c);
        if (r != null) mb = mb == null ? r : mb.expandToInclude(r);
      }
      if (mb == null) return null;
      b = mb.intersect(mask.region);
    }
    if (b.isEmpty) return null;
    return b.inflate(1);
  }

  Rect? _bounds(SvgNode n, {bool includeOwn = true}) {
    if (!n.display || !n.visible) return null;
    Rect? out;
    if (n.tag == 'g' || n.tag == 'svg') {
      for (final c in n.children) {
        final b = _bounds(c);
        if (b != null) out = out == null ? b : out.expandToInclude(b);
      }
    } else if (n.tag == 'use') {
      if (n.ref != null) out = _bounds(n.ref!);
    } else {
      out = n.getBBox();
      var half = 0.0;
      if (n.stroke != null || n.parent?.stroke != null || _inheritsStroke(n)) {
        half = (n.strokeWidth ?? _inheritedWidth(n)) / 2 + 1;
      }
      out = out.inflate(half);
    }
    if (out == null) return null;
    if (n.clip != null) {
      final c = n.clip!;
      if (c.shapes.length == 1 && c.shapes.first.tag == 'rect') {
        final r = c.shapes.first;
        out = out.intersect(Rect.fromLTWH(r.x, r.y, r.width, r.height));
      }
    }
    return includeOwn && n.transform != null ? n.transform!.mapRect(out) : out;
  }

  bool _inheritsStroke(SvgNode n) {
    for (SvgNode? p = n.parent; p != null; p = p.parent) {
      if (p.stroke != null) return true;
    }
    return false;
  }

  double _inheritedWidth(SvgNode n) {
    for (SvgNode? p = n.parent; p != null; p = p.parent) {
      if (p.strokeWidth != null) return p.strokeWidth!;
    }
    return 1;
  }
}

