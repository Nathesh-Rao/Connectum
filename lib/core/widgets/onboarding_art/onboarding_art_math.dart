import 'dart:math' as math;
import 'dart:ui';

import 'svg_path_parser.dart';

/// Easing and helper functions ported 1:1 from the authored animation scripts.
double clamp01(double v, [double a = 0, double b = 1]) =>
    math.min(b, math.max(a, v));

double lerp(double a, double b, double t) => a + (b - a) * t;

double eInOutCubic(double t) =>
    t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

double eOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();

double eInCubic(double t) => t * t * t;

double eOutBack(double t, [double s = 1.70158]) =>
    1 + (s + 1) * math.pow(t - 1, 3) + s * math.pow(t - 1, 2);

double spring(double u, double amp, double decay, double freq) =>
    u <= 0 ? 0 : amp * math.exp(-decay * u) * math.cos(freq * u);

/// JS `Math.round(v * 100) / 100`.
double round2(double v) => (v * 100 + 0.5).floorToDouble() / 100;

/// JS `Number(v.toFixed(n))` (the scripts store rounded values in attributes).
double toFixed(double v, int n) {
  final p = math.pow(10, n).toDouble();
  return (v * p).roundToDouble() / p;
}

/// `seg(t, s, d)` of the network and buildings scripts.
double seg(double t, double s, double d) => clamp01((t - s) / d);

double bump(double u) =>
    (u > 0 && u < 1) ? math.pow(math.sin(math.pi * u), 2).toDouble() : 0;

double dist2(List<double> a, List<double> b) =>
    math.sqrt(math.pow(b[0] - a[0], 2) + math.pow(b[1] - a[1], 2));

List<double> lerp2(List<double> a, List<double> b, double u) => [
  a[0] + (b[0] - a[0]) * u,
  a[1] + (b[1] - a[1]) * u,
];

/// `xf()` of the shield script: transform around a centre, scales and rotation
/// rounded to two decimals like the authored attribute strings.
Tf xf(
  double cx,
  double cy,
  double sc, [
  double rot = 0,
  double sx = 1,
  double sy = 1,
]) => Tf.identity
    .translate(cx, cy)
    .rotate(round2(rot))
    .scale(round2(sc * sx), round2(sc * sy))
    .translate(-cx, -cy);

/// `mix()` of the shield script (colour interpolation, channel rounding).
Color mixColor(Color a, Color b, double t) {
  int ch(double x, double y) => (lerp(x * 255, y * 255, t) + 0.5).floor().clamp(0, 255);
  return Color.fromARGB(255, ch(a.r, b.r), ch(a.g, b.g), ch(a.b, b.b));
}
