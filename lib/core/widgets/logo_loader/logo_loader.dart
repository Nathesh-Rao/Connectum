import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'logo_data.dart';

/// The four states of the loader.
enum LogoLoaderState { idle, starting, loading, stopping }

/// Tunable settings (same names and values as `CFG.loader` in the HTML preview).
class LogoLoaderConfig {
  const LogoLoaderConfig({
    this.startMorph = 0.9, // s  – C → O morph at full speed
    this.morphRamp = 0.28, // s  – how quickly the morph velocity builds up
    this.startSpeed = 45, // deg/s – the slow crawl the rotation starts from
    this.baseSpeed = 400, // deg/s – average loading speed
    this.tau = 0.4, // s  – velocity smoothing (speed glides, never jumps)
    this.maxAccel = 1100, // deg/s² – cap on angular acceleration
    this.rhythm = 1, // strength of the slow speed waves (0 = constant speed)
    this.burstMin = 0.28,
    this.burstMax = 0.5, // size of the gentle surges (× base speed)
    this.minFactor = 0.5,
    this.maxFactor = 1.9, // speed stays within 0.5× … 1.9× of baseSpeed
    this.stopMin = 0.9,
    this.stopMax = 2.2, // s – allowed duration of the O → C transition
    this.segments = 8, // number of ring segments (gaps)
    this.gap = 13, // width of each gap (SVG units)
    this.swirl = 0.42, // rad of extra inner twist while morphing
    this.overlap = 0.075, // rad the two ends overlap when they join
    this.tailBias = 1.5,
  });

  final double startMorph,
      morphRamp,
      startSpeed,
      baseSpeed,
      tau,
      maxAccel,
      rhythm;
  final double burstMin, burstMax, minFactor, maxFactor, stopMin, stopMax;
  final int segments;
  final double gap, swirl, overlap, tailBias;
}

/// Drives the animation. Create one, pass it to [LogoLoader], then call
/// [start] / [stop]. Safe to call repeatedly and in any order.
class LogoLoaderController extends ChangeNotifier {
  LogoLoaderController({
    this.config = const LogoLoaderConfig(),
    math.Random? random,
  }) : _rnd = random ?? math.Random() {
    _rhythm = _Rhythm(config, _rnd);
  }

  final LogoLoaderConfig config;
  final math.Random _rnd;

  LogoLoaderState _state = LogoLoaderState.idle;
  LogoLoaderState get state => _state;
  bool get isIdle => _state == LogoLoaderState.idle;

  /// Morph progress (0 = original C, 1 = finished O) and its velocity (1/s).
  double p = 0, pv = 0;

  /// Clockwise rotation in degrees and angular velocity in deg/s.
  double theta = 0, omega = 0;

  double _tRun = 0;
  _StopPlan? _plan;
  late _Rhythm _rhythm;
  final List<Completer<void>> _idleWaiters = [];
  int _mounts = 0;
  bool _isDisposed = false;

  /// Begin C → O and start spinning. Ignored while already starting / loading.
  /// Called during STOPPING it turns around smoothly from the current motion.
  bool start() {
    if (_isDisposed) return false;
    if (_state == LogoLoaderState.starting || _state == LogoLoaderState.loading) {
      return false;
    }
    _rhythm = _Rhythm(config, _rnd);
    _tRun = 0;
    _plan = null;
    if (_state == LogoLoaderState.idle) {
      p = 0;
      pv = 0;
      theta = 0;
      omega = 0;
    } else {
      theta = theta % 360;
    }
    _setState(LogoLoaderState.starting);
    return true;
  }

  /// Leave the loading rhythm, turn O → C and land exactly on the original C.
  /// Ignored while idle / already stopping.
  bool stop() {
    if (_isDisposed ||
        _state == LogoLoaderState.idle ||
        _state == LogoLoaderState.stopping) {
      return false;
    }
    if (_mounts == 0) {
      // nothing drives the simulation: land on the C at once instead of hanging waiters
      _resetToIdle(shouldNotify: true);
      return false;
    }
    _plan = _planStop();
    _setState(LogoLoaderState.stopping);
    return true;
  }

  /// Completes when the logo is back to the exact C (state idle).
  Future<void> get whenIdle {
    if (_state == LogoLoaderState.idle) return Future<void>.value();
    final c = Completer<void>();
    _idleWaiters.add(c);
    return c.future;
  }

  /// `stop()` and wait until the C is fully restored.
  Future<void> stopAndWait() {
    stop();
    return whenIdle;
  }

  /// Convenience: spin while [task] runs, then stop and wait for the C.
  Future<T> run<T>(Future<T> Function() task) async {
    start();
    try {
      return await task();
    } finally {
      await stopAndWait();
    }
  }

  void _attach() => _mounts++;

  void _detach() {
    if (_mounts > 0) _mounts--;
    if (_mounts == 0 && !_isDisposed && !isIdle) {
      _resetToIdle(shouldNotify: false);
    }
  }

  void _resetToIdle({required bool shouldNotify}) {
    p = 0;
    pv = 0;
    theta = 0;
    omega = 0;
    _plan = null;
    _state = LogoLoaderState.idle;
    _completeWaiters();
    if (shouldNotify) notifyListeners();
  }

  void _completeWaiters() {
    for (final c in _idleWaiters) {
      if (!c.isCompleted) c.complete();
    }
    _idleWaiters.clear();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _completeWaiters();
    super.dispose();
  }

  void _setState(LogoLoaderState next) {
    if (_state == next) return;
    _state = next;
    if (next == LogoLoaderState.idle) _completeWaiters();
    notifyListeners();
  }

  // ---------------------------------------------------------------- simulation

  /// Advance the simulation by [dt] seconds (called by the widget's ticker).
  void step(double dt) {
    if (_isDisposed || _state == LogoLoaderState.idle || dt <= 0) return;
    final c = config;

    if (_state == LogoLoaderState.stopping) {
      final pl = _plan!;
      pl.s += dt / pl.ts;
      if (pl.s >= 1) {
        // C restored: exact original geometry and orientation.
        p = 0;
        pv = 0;
        theta = 0;
        omega = 0;
        _plan = null;
        _setState(LogoLoaderState.idle);
        notifyListeners();
        return;
      }
      final hp = _hermite(pl.s, pl.p0, pl.pv0 * pl.ts, 0, 0);
      final ht = _hermite(pl.s, pl.th0, pl.w0 * pl.ts, pl.th0 + pl.d, 0);
      p = hp[0].clamp(0.0, 1.0).toDouble();
      pv = hp[1] / pl.ts;
      theta = ht[0];
      omega = ht[1] / pl.ts;
      notifyListeners();
      return;
    }

    // STARTING / LOADING
    _tRun += dt;
    if (_state == LogoLoaderState.starting) {
      final vT = 1 / c.startMorph;
      final a = vT / c.morphRamp;
      pv += (vT - pv).clamp(-a * dt, a * dt).toDouble();
      p += pv * dt;
    }
    final wT = _lerp(c.startSpeed, c.baseSpeed * _rhythm.at(_tRun), _ramp(p));
    final lim = c.maxAccel * dt;
    omega += ((wT - omega) * (1 - math.exp(-dt / c.tau)))
        .clamp(-lim, lim)
        .toDouble();
    theta += omega * dt;
    if (_state == LogoLoaderState.starting && p >= 1) {
      p = 1;
      pv = 0;
      _setState(LogoLoaderState.loading);
    }
    notifyListeners();
  }

  static double _ramp(double p) {
    final x = ((p - 0.05) / 0.95).clamp(0.0, 1.0).toDouble();
    return x * x * (3 - 2 * x);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static List<double> _hermite(
    double s,
    double x0,
    double v0,
    double x1,
    double v1,
  ) {
    final s2 = s * s, s3 = s2 * s;
    return [
      (2 * s3 - 3 * s2 + 1) * x0 +
          (s3 - 2 * s2 + s) * v0 +
          (-2 * s3 + 3 * s2) * x1 +
          (s3 - s2) * v1,
      (6 * s2 - 6 * s) * x0 +
          (3 * s2 - 4 * s + 1) * v0 +
          (-6 * s2 + 6 * s) * x1 +
          (3 * s2 - 2 * s) * v1,
    ];
  }

  /// Plans the way out: the rotation must end exactly on a multiple of 360°
  /// (the original orientation) when p reaches 0, without ever reversing.
  _StopPlan _planStop() {
    final c = config;
    final th0 = theta % 360;
    final w0 = math.max(omega, 0.0);
    double? d;
    double ts = c.stopMin;
    if (th0 <= 20 && w0 <= 30) {
      // barely started: just settle back gently
      d = -th0;
      ts = c.stopMin + 0.2;
    } else {
      final d0 = (360 - th0) % 360;
      final w = math.max(w0, 1e-3);
      for (var j = 0; j < 6 && d == null; j++) {
        final cand = d0 + 360.0 * j;
        if (cand < 1e-6) continue;
        final lo = math.max(c.stopMin, 1.25 * cand / w);
        final hi = math.min(c.stopMax, 3 * cand / w);
        if (lo <= hi) {
          d = cand;
          ts = (2 * cand / w).clamp(lo, hi).toDouble();
        }
      }
      if (d == null) {
        d = d0 < 120 ? d0 + 360 : d0;
        ts = c.stopMax * 0.8;
      }
    }
    return _StopPlan(ts: ts, th0: th0, d: d, w0: w0, p0: p, pv0: pv);
  }
}

class _StopPlan {
  _StopPlan({
    required this.ts,
    required this.th0,
    required this.d,
    required this.w0,
    required this.p0,
    required this.pv0,
  });
  final double ts, th0, d, w0, p0, pv0;
  double s = 0;
}

/// Organic speed rhythm: slow waves with unrelated periods and a drifting
/// amplitude (never repeats) plus occasional gentle bursts followed by a lull.
class _Rhythm {
  _Rhythm(this.c, this.rnd) {
    ph = List<double>.generate(5, (_) => _r(0, math.pi * 2));
    per = [3.7, 6.1, 10.3, 1.9, 17.3].map((v) => v * _r(0.92, 1.08)).toList();
    next = _r(1.2, 3.0);
  }
  final LogoLoaderConfig c;
  final math.Random rnd;
  late final List<double> ph, per;
  late double next;
  final List<List<double>> bursts = []; // [t0, dur, amp]

  double _r(double a, double b) => a + rnd.nextDouble() * (b - a);
  double _bump(double u) =>
      (u <= 0 || u >= 1) ? 0 : math.pow(math.sin(math.pi * u), 2).toDouble();

  double at(double t) {
    const tau = math.pi * 2;
    while (t >= next) {
      final dur = _r(1.0, 1.8), amp = _r(c.burstMin, c.burstMax);
      bursts.add([next, dur, amp]);
      next += dur * 2.6 + _r(1.2, 4.5);
    }
    bursts.removeWhere((b) => t >= b[0] + b[1] * 2.6);
    final am = 1 + 0.3 * math.sin(tau * t / per[4] + ph[4]);
    var m =
        1 +
        c.rhythm *
            am *
            (0.17 * math.sin(tau * t / per[0] + ph[0]) +
                0.12 * math.sin(tau * t / per[1] + ph[1]) +
                0.08 * math.sin(tau * t / per[2] + ph[2]) +
                0.04 * math.sin(tau * t / per[3] + ph[3]));
    for (final b in bursts) {
      m +=
          b[2] * _bump((t - b[0]) / b[1]) -
          0.55 * b[2] * _bump((t - b[0] - b[1] * 0.9) / (b[1] * 1.7));
    }
    return m.clamp(c.minFactor, c.maxFactor).toDouble();
  }
}

// =============================================================================
// Widget
// =============================================================================

/// The animated logo. Control it with a [LogoLoaderController].
class LogoLoader extends StatefulWidget {
  const LogoLoader({super.key, required this.controller, this.size = 120});

  final LogoLoaderController controller;

  /// Width and height of the (square) logo.
  final double size;

  @override
  State<LogoLoader> createState() => _LogoLoaderState();
}

class _LogoLoaderState extends State<LogoLoader>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller._attach();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(LogoLoader old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_sync);
      old.controller._detach();
      widget.controller._attach();
      widget.controller.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    if (!widget.controller.isIdle && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6)
        .clamp(0.0, 0.05)
        .toDouble();
    _last = elapsed;
    widget.controller.step(dt);
    if (widget.controller.isIdle) _ticker.stop();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    widget.controller._detach();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(painter: _LogoPainter(widget.controller)),
      ),
    );
  }
}

// =============================================================================
// Painter
// =============================================================================

class _Shared {
  _Shared._() {
    originals = buildOriginalPaths();
    for (final p in kLogoPolys) {
      r.add(Float64List.fromList(p.r));
      a.add(Float64List.fromList(p.a));
      rf.add(Float64List.fromList(p.rf));
      paints.add(
        Paint()
          ..color = Color(p.color)
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
    }
  }
  static final _Shared i = _Shared._();
  late final List<Path> originals;
  final List<Float64List> r = [], a = [], rf = [];
  final List<Paint> paints = [];

  // cache of the finished ring (p == 1): polygons never change, only the rotation does
  List<Path>? ringPaths;
  Path? ringMask;
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.ctl) : super(repaint: ctl);
  final LogoLoaderController ctl;

  static const double _pi = math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final sh = _Shared.i;
    final c = ctl.config;
    final s = math.min(size.width, size.height) / 1024.0;
    canvas.save();
    canvas.translate((size.width - 1024 * s) / 2, (size.height - 1024 * s) / 2);
    canvas.scale(s);

    final p = ctl.p;
    if (p <= 0) {
      // exact original C
      for (var i = 0; i < LogoGeo.count; i++) {
        canvas.drawPath(sh.originals[i], sh.paints[i]);
      }
      canvas.restore();
      return;
    }

    const cx = LogoGeo.cx, cy = LogoGeo.cy;
    final rot = ((ctl.theta % 360) * _pi / 180);
    canvas.translate(cx, cy);
    canvas.rotate(rot);
    canvas.translate(-cx, -cy);

    late final List<Path> paths;
    late final Path mask;
    if (p >= 1 && sh.ringPaths != null) {
      paths = sh.ringPaths!;
      mask = sh.ringMask!;
    } else {
      final eA = _easeInOutCubic(((p) / 0.82).clamp(0.0, 1.0).toDouble());
      final eR = _easeInOutCubic(
        ((p - 0.18) / 0.82).clamp(0.0, 1.0).toDouble(),
      );
      final sw = math.sin(_pi * _easeInOutSine(p)) * c.swirl;
      var rmin = double.infinity, rmax = 0.0;
      paths = List<Path>.generate(LogoGeo.count, (i) {
        final r = sh.r[i], a = sh.a[i], rf = sh.rf[i];
        final path = Path();
        for (var k = 0; k < r.length; k++) {
          final rr = r[k] + (rf[k] - r[k]) * eR;
          if (rr < rmin) rmin = rr;
          if (rr > rmax) rmax = rr;
          final ang =
              LogoGeo.phiC +
              _angWarp(a[k], eA, c) +
              sw * (1 - (rr / LogoGeo.rOut).clamp(0.0, 1.0).toDouble());
          final x = cx + rr * math.cos(ang), y = cy + rr * math.sin(ang);
          if (k == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        return path;
      }, growable: false);

      // exact circular boundaries: slide in from the current extent to the final radii
      final w = eR * eR * (3 - 2 * eR);
      final ro = (rmax + 2) + (LogoGeo.rOut - (rmax + 2)) * w;
      final ri =
          math.max(0.0, rmin - 2) + (LogoGeo.rIn - math.max(0.0, rmin - 2)) * w;
      final wg = ((eR - 0.5) / 0.5).clamp(0.0, 1.0).toDouble();
      mask = _ringMask(ro, ri, c.gap * wg * wg * (3 - 2 * wg), c);
      if (p >= 1) {
        sh.ringPaths = paths;
        sh.ringMask = mask;
      }
    }

    canvas.clipPath(mask, doAntiAlias: true);
    for (var i = 0; i < paths.length; i++) {
      canvas.drawPath(paths[i], sh.paints[i]);
    }
    canvas.restore();
  }

  static Path _ringMask(double ro, double ri, double gapW, LogoLoaderConfig c) {
    const center = Offset(LogoGeo.cx, LogoGeo.cy);
    final ring = Path()..fillType = PathFillType.evenOdd;
    ring.addOval(Rect.fromCircle(center: center, radius: ro));
    if (ri > 0.5) ring.addOval(Rect.fromCircle(center: center, radius: ri));
    if (gapW <= 0.01) return ring;
    // radial gap strips, one centred on the seam where the two ends join
    final gaps = Path();
    final r0 = LogoGeo.rIn - 40, r1 = LogoGeo.rOut + 40, h = gapW / 2;
    for (var n = 0; n < c.segments; n++) {
      final th = LogoGeo.phiC + n * 2 * _pi / c.segments;
      final ux = math.cos(th), uy = math.sin(th), vx = -uy, vy = ux;
      gaps.moveTo(LogoGeo.cx + r0 * ux - h * vx, LogoGeo.cy + r0 * uy - h * vy);
      gaps.lineTo(LogoGeo.cx + r1 * ux - h * vx, LogoGeo.cy + r1 * uy - h * vy);
      gaps.lineTo(LogoGeo.cx + r1 * ux + h * vx, LogoGeo.cy + r1 * uy + h * vy);
      gaps.lineTo(LogoGeo.cx + r0 * ux + h * vx, LogoGeo.cy + r0 * uy + h * vy);
      gaps.close();
    }
    return Path.combine(PathOperation.difference, ring, gaps);
  }

  /// Stretches the body towards the opening so both ends meet (e: 0 → original, 1 → closed ring).
  static double _angWarp(double a, double e, LogoLoaderConfig c) {
    final sg = a < 0 ? -1.0 : 1.0;
    final m = a.abs();
    final mEnd = LogoGeo.g0 * (1 - e) - c.overlap * e;
    double m2;
    if (m >= LogoGeo.g0) {
      final u = ((m - LogoGeo.g0) / (_pi - LogoGeo.g0))
          .clamp(0.0, 1.0)
          .toDouble();
      m2 = m + (mEnd - LogoGeo.g0) * math.pow(1 - u, c.tailBias).toDouble();
    } else {
      m2 = m * (mEnd / LogoGeo.g0);
    }
    return sg * m2;
  }

  static double _easeInOutCubic(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;
  static double _easeInOutSine(double t) => -(math.cos(_pi * t) - 1) / 2;

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.ctl != ctl;
}
