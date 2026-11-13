import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A parsed SVG path: the dart:ui [Path] and the exact (tight, stroke-less)
/// bounding box that `getBBox()` returns in a browser.
class ParsedPath {
  const ParsedPath(this.path, this.bounds);

  final Path path;
  final Rect bounds;
}

class _Box {
  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = double.negativeInfinity;
  double maxY = double.negativeInfinity;

  void add(double x, double y) {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }

  void cubic(
    double x0,
    double y0,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    add(x3, y3);
    for (final t in _roots(x0, x1, x2, x3)) {
      add(_cubicAt(x0, x1, x2, x3, t), _cubicAt(y0, y1, y2, y3, t));
    }
    for (final t in _roots(y0, y1, y2, y3)) {
      add(_cubicAt(x0, x1, x2, x3, t), _cubicAt(y0, y1, y2, y3, t));
    }
  }

  static double _cubicAt(double a, double b, double c, double d, double t) {
    final u = 1 - t;
    return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d;
  }

  static List<double> _roots(double p0, double p1, double p2, double p3) {
    final a = -p0 + 3 * p1 - 3 * p2 + p3;
    final b = 2 * (p0 - 2 * p1 + p2);
    final c = p1 - p0;
    final out = <double>[];
    if (a.abs() < 1e-12) {
      if (b.abs() > 1e-12) out.add(-c / b);
    } else {
      final disc = b * b - 4 * a * c;
      if (disc >= 0) {
        final s = math.sqrt(disc);
        out
          ..add((-b + s) / (2 * a))
          ..add((-b - s) / (2 * a));
      }
    }
    return out.where((t) => t > 0 && t < 1).toList();
  }

  Rect get rect => minX.isFinite
      ? Rect.fromLTRB(minX, minY, maxX, maxY)
      : Rect.zero;
}

class _Scan {
  _Scan(this.s);

  final String s;
  int i = 0;

  bool get done {
    skip();
    return i >= s.length;
  }

  void skip() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x2C || c == 0x0A || c == 0x09 || c == 0x0D) {
        i++;
      } else {
        break;
      }
    }
  }

  bool get atNumber {
    skip();
    if (i >= s.length) return false;
    final c = s.codeUnitAt(i);
    return (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E;
  }

  double number() {
    skip();
    final start = i;
    if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
    var seenDot = false;
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) {
        i++;
      } else if (c == 0x2E && !seenDot) {
        seenDot = true;
        i++;
      } else {
        break;
      }
    }
    if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
      final save = i;
      i++;
      if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
      final digits = i;
      while (i < s.length && s.codeUnitAt(i) >= 0x30 && s.codeUnitAt(i) <= 0x39) {
        i++;
      }
      if (i == digits) i = save;
    }
    if (i == start) throw FormatException('number expected at $i in "$s"');
    return double.parse(s.substring(start, i));
  }

  bool flag() {
    skip();
    final c = s[i++];
    if (c != '0' && c != '1') throw FormatException('flag expected at $i');
    return c == '1';
  }
}

/// Parses SVG path data: M m L l H h V v C c S s Q q T t A a Z z, implicit
/// repeats and compact numbers like `1.5-2.3`.
ParsedPath parseSvgPath(String d) {
  final sc = _Scan(d);
  final path = Path();
  final box = _Box();
  double x = 0, y = 0, sx = 0, sy = 0;
  double? lcx, lcy; // last cubic control (for S)
  double? lqx, lqy; // last quad control (for T)
  String? cmd;
  var hasMove = false;

  while (!sc.done) {
    final c = sc.s[sc.i];
    final isLetter = RegExp(r'[A-Za-z]').hasMatch(c);
    if (isLetter) {
      cmd = c;
      sc.i++;
    } else if (cmd == null) {
      throw FormatException('path must start with a command: "$d"');
    } else if (cmd == 'M') {
      cmd = 'L';
    } else if (cmd == 'm') {
      cmd = 'l';
    }
    final rel = cmd == cmd.toLowerCase();
    final up = cmd.toUpperCase();
    final ox = rel ? x : 0.0;
    final oy = rel ? y : 0.0;
    var nextCubic = false;
    var nextQuad = false;
    switch (up) {
      case 'Z':
        if (hasMove) path.close();
        x = sx;
        y = sy;
      case 'M':
        x = ox + sc.number();
        y = oy + sc.number();
        sx = x;
        sy = y;
        path.moveTo(x, y);
        box.add(x, y);
        hasMove = true;
      case 'L':
        x = ox + sc.number();
        y = oy + sc.number();
        path.lineTo(x, y);
        box.add(x, y);
      case 'H':
        x = ox + sc.number();
        path.lineTo(x, y);
        box.add(x, y);
      case 'V':
        y = oy + sc.number();
        path.lineTo(x, y);
        box.add(x, y);
      case 'C':
        final x1 = ox + sc.number(), y1 = oy + sc.number();
        final x2 = ox + sc.number(), y2 = oy + sc.number();
        final x3 = ox + sc.number(), y3 = oy + sc.number();
        path.cubicTo(x1, y1, x2, y2, x3, y3);
        box.cubic(x, y, x1, y1, x2, y2, x3, y3);
        lcx = x2;
        lcy = y2;
        nextCubic = true;
        x = x3;
        y = y3;
      case 'S':
        final x1 = lcx != null ? 2 * x - lcx : x;
        final y1 = lcy != null ? 2 * y - lcy : y;
        final x2 = ox + sc.number(), y2 = oy + sc.number();
        final x3 = ox + sc.number(), y3 = oy + sc.number();
        path.cubicTo(x1, y1, x2, y2, x3, y3);
        box.cubic(x, y, x1, y1, x2, y2, x3, y3);
        lcx = x2;
        lcy = y2;
        nextCubic = true;
        x = x3;
        y = y3;
      case 'Q':
        final x1 = ox + sc.number(), y1 = oy + sc.number();
        final x2 = ox + sc.number(), y2 = oy + sc.number();
        _quad(path, box, x, y, x1, y1, x2, y2);
        lqx = x1;
        lqy = y1;
        nextQuad = true;
        x = x2;
        y = y2;
      case 'T':
        final x1 = lqx != null ? 2 * x - lqx : x;
        final y1 = lqy != null ? 2 * y - lqy : y;
        final x2 = ox + sc.number(), y2 = oy + sc.number();
        _quad(path, box, x, y, x1, y1, x2, y2);
        lqx = x1;
        lqy = y1;
        nextQuad = true;
        x = x2;
        y = y2;
      case 'A':
        final rx = sc.number(), ry = sc.number(), rot = sc.number();
        final large = sc.flag(), sweep = sc.flag();
        final x2 = ox + sc.number(), y2 = oy + sc.number();
        _arc(path, box, x, y, rx, ry, rot, large, sweep, x2, y2);
        x = x2;
        y = y2;
      default:
        throw FormatException('unknown path command "$cmd" in "$d"');
    }
    if (!nextCubic) {
      lcx = null;
      lcy = null;
    }
    if (!nextQuad) {
      lqx = null;
      lqy = null;
    }
    if (up == 'Z') cmd = null;
  }
  return ParsedPath(path, box.rect);
}

void _quad(
  Path p,
  _Box box,
  double x0,
  double y0,
  double x1,
  double y1,
  double x2,
  double y2,
) {
  p.quadraticBezierTo(x1, y1, x2, y2);
  // exact bounds through the equivalent cubic
  box.cubic(
    x0,
    y0,
    x0 + 2 / 3 * (x1 - x0),
    y0 + 2 / 3 * (y1 - y0),
    x2 + 2 / 3 * (x1 - x2),
    y2 + 2 / 3 * (y1 - y2),
    x2,
    y2,
  );
}

void _arc(
  Path p,
  _Box box,
  double x1,
  double y1,
  double rxIn,
  double ryIn,
  double rotDeg,
  bool large,
  bool sweep,
  double x2,
  double y2,
) {
  var rx = rxIn.abs(), ry = ryIn.abs();
  if (rx == 0 || ry == 0 || (x1 == x2 && y1 == y2)) {
    p.lineTo(x2, y2);
    box.add(x2, y2);
    return;
  }
  final phi = rotDeg * math.pi / 180;
  final cp = math.cos(phi), sp = math.sin(phi);
  final dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
  final x1p = cp * dx + sp * dy;
  final y1p = -sp * dx + cp * dy;
  final lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
  if (lam > 1) {
    final s = math.sqrt(lam);
    rx *= s;
    ry *= s;
  }
  final num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
  final den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
  var co = math.sqrt(math.max(0, num / den));
  if (large == sweep) co = -co;
  final cxp = co * rx * y1p / ry;
  final cyp = -co * ry * x1p / rx;
  final cx = cp * cxp - sp * cyp + (x1 + x2) / 2;
  final cy = sp * cxp + cp * cyp + (y1 + y2) / 2;
  double ang(double ux, double uy, double vx, double vy) {
    final a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
    return a;
  }

  final th1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
  var dth = ang(
    (x1p - cxp) / rx,
    (y1p - cyp) / ry,
    (-x1p - cxp) / rx,
    (-y1p - cyp) / ry,
  );
  if (!sweep && dth > 0) dth -= 2 * math.pi;
  if (sweep && dth < 0) dth += 2 * math.pi;
  final n = (dth.abs() / (math.pi / 2)).ceil().clamp(1, 8);
  final step = dth / n;
  final k = 4 / 3 * math.tan(step / 4);
  var t = th1;
  var px = x1, py = y1;
  for (var i = 0; i < n; i++) {
    final c1 = math.cos(t), s1 = math.sin(t);
    final c2 = math.cos(t + step), s2 = math.sin(t + step);
    double ex(double c, double s) => cp * rx * c - sp * ry * s + cx;
    double ey(double c, double s) => sp * rx * c + cp * ry * s + cy;
    final cax = px + k * (-cp * rx * s1 - sp * ry * c1);
    final cay = py + k * (-sp * rx * s1 + cp * ry * c1);
    final ex2 = i == n - 1 ? x2 : ex(c2, s2);
    final ey2 = i == n - 1 ? y2 : ey(c2, s2);
    final cbx = ex2 - k * (-cp * rx * s2 - sp * ry * c2);
    final cby = ey2 - k * (-sp * rx * s2 + cp * ry * c2);
    p.cubicTo(cax, cay, cbx, cby, ex2, ey2);
    box.cubic(px, py, cax, cay, cbx, cby, ex2, ey2);
    px = ex2;
    py = ey2;
    t += step;
  }
}

/// A 2D affine transform, composed in SVG list order: `translate(a) rotate(b)`
/// is `Tf.identity.translate(..).rotate(..)`.
class Tf {
  const Tf(this.a, this.b, this.c, this.d, this.e, this.f);

  static const identity = Tf(1, 0, 0, 1, 0, 0);

  final double a, b, c, d, e, f;

  Tf then(Tf o) => Tf(
    a * o.a + c * o.b,
    b * o.a + d * o.b,
    a * o.c + c * o.d,
    b * o.c + d * o.d,
    a * o.e + c * o.f + e,
    b * o.e + d * o.f + f,
  );

  Tf translate(double x, [double y = 0]) => then(Tf(1, 0, 0, 1, x, y));

  Tf scale(double sx, [double? sy]) => then(Tf(sx, 0, 0, sy ?? sx, 0, 0));

  Tf rotate(double deg, [double cx = 0, double cy = 0]) {
    final r = deg * math.pi / 180;
    final co = math.cos(r), si = math.sin(r);
    final rot = Tf(co, si, -si, co, 0, 0);
    if (cx == 0 && cy == 0) return then(rot);
    return translate(cx, cy).then(rot).translate(-cx, -cy);
  }

  Float64List toMatrix4() => Float64List.fromList([
    a, b, 0, 0, //
    c, d, 0, 0,
    0, 0, 1, 0,
    e, f, 0, 1,
  ]);

  Rect mapRect(Rect r) {
    final xs = <double>[];
    final ys = <double>[];
    for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      xs.add(a * p.dx + c * p.dy + e);
      ys.add(b * p.dx + d * p.dy + f);
    }
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  /// Parses an SVG transform list: translate, scale, rotate(a [cx cy]), matrix.
  static Tf parse(String s) {
    var t = identity;
    for (final m in RegExp(r'(\w+)\s*\(([^)]*)\)').allMatches(s)) {
      final v = m[2]!
          .split(RegExp(r'[\s,]+'))
          .where((e) => e.isNotEmpty)
          .map(double.parse)
          .toList();
      switch (m[1]) {
        case 'translate':
          t = t.translate(v[0], v.length > 1 ? v[1] : 0);
        case 'scale':
          t = t.scale(v[0], v.length > 1 ? v[1] : v[0]);
        case 'rotate':
          t = t.rotate(v[0], v.length > 2 ? v[1] : 0, v.length > 2 ? v[2] : 0);
        case 'matrix':
          t = t.then(Tf(v[0], v[1], v[2], v[3], v[4], v[5]));
        default:
          throw FormatException('unsupported transform "${m[1]}"');
      }
    }
    return t;
  }
}
