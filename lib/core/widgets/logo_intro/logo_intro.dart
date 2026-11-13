import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_colors.dart';
import 'logo_intro_data.dart';

/// Lets you replay the intro from code:  `controller.replay();`
class LogoIntroController extends ChangeNotifier {
  int _token = 0;
  int get token => _token;

  /// Restart the animation from the beginning.
  void replay() {
    _token++;
    notifyListeners();
  }
}

/// One-time intro: a solid ball (the top end of the C) → the C grows out of it, piece after piece →
/// the CONNECTUM wordmark enters with a blur/tracking reveal, light sweep and glow.
///
/// Draws on a transparent background. Everything is a pure function of time, so it is smooth
/// at any frame rate. No packages needed.
class LogoIntro extends StatefulWidget {
  const LogoIntro({
    super.key,
    this.size,
    this.controller,
    this.autoPlay = true,
    this.onFinished,
    this.ink = AppColors.ink, // wordmark colour
    this.shine = AppColors.white, // light-sweep colour
    this.ball = AppColors.primaryBright, // the solid starting ball
    this.glowInner = AppColors.primaryBright,
    this.glowOuter = AppColors.primaryLight,
    this.speed = 1.0,
    this.finishAt = IntroTiming.duration,
    this.timeOverride,
    this.blurLetters = true,
    this.glowFinal = 0.55,
  });

  /// Width = height in logical pixels. If null, fills the available square.
  final double? size;
  final LogoIntroController? controller;
  final bool autoPlay;

  /// Called once when the authored time reaches [finishAt] (the logo then stays
  /// as the final still). Never called while [timeOverride] drives the painter.
  final VoidCallback? onFinished;
  final Color ink, shine, ball, glowInner, glowOuter;

  /// Scales elapsed time (2 = twice as fast). Authored times stay in seconds.
  final double speed;

  /// Seconds on the AUTHORED timeline at which [onFinished] fires. The animation
  /// keeps playing to its end.
  final double finishAt;

  /// When set, the painter uses this time (authored seconds) instead of the
  /// ticker and no ticker runs. For the debug scrubber and golden tests.
  final ValueListenable<double>? timeOverride;

  /// False turns off the blur of the letters (fallback for slow devices).
  final bool blurLetters;

  /// 0..1 strength of the persistent bloom under the name in the final still.
  final double glowFinal;

  /// Total length of the animation in seconds.
  static const double duration = IntroTiming.duration;

  @override
  State<LogoIntro> createState() => _LogoIntroState();
}

class _LogoIntroState extends State<LogoIntro>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  late final _IntroGeometry _geo;
  bool _finishedSent = false;
  bool _isReduced = false;
  bool _isInitialised = false;
  double _t = 0; // authored seconds
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _geo = _IntroGeometry();
    _ticker = createTicker(_onTick);
    widget.controller?.addListener(_onController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final changed = reduced != _isReduced;
    _isReduced = reduced;
    if (!_isInitialised) {
      _isInitialised = true;
      if (widget.autoPlay) _start();
    } else if (changed && reduced) {
      _start();
    }
  }

  @override
  void didUpdateWidget(covariant LogoIntro old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onController);
      widget.controller?.addListener(_onController);
    }
    if (old.timeOverride != widget.timeOverride) {
      if (widget.timeOverride != null) {
        _ticker.stop();
      } else if (widget.autoPlay) {
        _start();
      }
    }
  }

  void _onController() => _start();

  void _onTick(Duration elapsed) {
    _t += (elapsed - _lastElapsed).inMicroseconds / 1e6 * widget.speed;
    _lastElapsed = elapsed;
    _time.value = _t.clamp(0.0, IntroTiming.duration);
    _checkFinished();
    if (_t >= IntroTiming.duration) _ticker.stop();
  }

  void _checkFinished() {
    if (_finishedSent) return;
    if (_t >= math.min(widget.finishAt, IntroTiming.duration)) {
      _finishedSent = true;
      widget.onFinished?.call();
    }
  }

  void _start() {
    _finishedSent = false;
    if (_ticker.isActive) _ticker.stop();
    _t = 0;
    _lastElapsed = Duration.zero;
    if (widget.timeOverride != null) return;
    if (_isReduced) {
      _t = IntroTiming.duration;
      _time.value = IntroTiming.duration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isReduced) _checkFinished();
      });
      return;
    }
    _time.value = 0;
    _ticker.start();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onController);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paint = RepaintBoundary(
      child: CustomPaint(
        painter: _IntroPainter(
          time: widget.timeOverride ?? _time,
          geo: _geo,
          ink: widget.ink,
          shine: widget.shine,
          ball: widget.ball,
          glowInner: widget.glowInner,
          glowOuter: widget.glowOuter,
          blurLetters: widget.blurLetters,
          glowFinal: widget.glowFinal,
        ),
      ),
    );
    if (widget.size != null) {
      return SizedBox(width: widget.size, height: widget.size, child: paint);
    }
    return AspectRatio(aspectRatio: 1, child: paint);
  }
}

// ---------------------------------------------------------------------------------------------
// Timing (seconds) – identical to the HTML version
// ---------------------------------------------------------------------------------------------
class IntroTiming {
  static const double pop = 0.55, grow0 = 1.05, grow = 1.75;
  static const double stagger = 0.07, letter = 0.9;
  static const double glint = 1.05, tail = 0.5;
  static const double grow1 = grow0 + grow; // 2.8
  static const double word = grow1 - 0.15; // 2.65
  static const double last = word + 8 * stagger + letter; // 4.11
  static const double glintAt = last - letter * 0.55 + 0.3; // 3.915
  static const double duration = glintAt + glint + tail; // 5.465
}

// ---------------------------------------------------------------------------------------------
// Easing helpers
// ---------------------------------------------------------------------------------------------
const double _pi = math.pi;
double _clamp(double v, [double a = 0, double b = 1]) =>
    v < a ? a : (v > b ? b : v);
double _lerp(double a, double b, double t) => a + (b - a) * t;
double _smooth(double t) => t * t * (3 - 2 * t);
double _eInOutCubic(double t) =>
    t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;
double _eInOutSine(double t) => -(math.cos(_pi * t) - 1) / 2;
double _eOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();
double _eOutQuart(double t) => 1 - math.pow(1 - t, 4).toDouble();
double _eOutBack(double t, [double s = 1.6]) =>
    1 +
    (s + 1) * math.pow(t - 1, 3).toDouble() +
    s * math.pow(t - 1, 2).toDouble();

// ---------------------------------------------------------------------------------------------
// Prepared geometry (built once)
// ---------------------------------------------------------------------------------------------
class _PreparedSub {
  _PreparedSub(this.src) {
    final n = src.pts.length ~/ 2;
    fx = Float64List(n);
    fy = Float64List(n);
    ca = Float64List(n);
    cosA = Float64List(n);
    sinA = Float64List(n);
    for (int k = 0; k < n; k++) {
      fx[k] = src.pts[2 * k] - src.mx;
      fy[k] = src.pts[2 * k + 1] - src.my;
      ca[k] = math.atan2(fy[k], fx[k]);
      cosA[k] = math.cos(ca[k]);
      sinA[k] = math.sin(ca[k]);
    }
  }
  final IntroSub src;
  late final Float64List fx, fy, ca, cosA, sinA;
  int get n => fx.length;
}

class _IntroGeometry {
  _IntroGeometry() {
    pieces = [
      for (final p in introPieces) [for (final s in p.subs) _PreparedSub(s)],
    ];
    original = buildIntroOriginalPaths();
    letters = buildIntroLetterPaths();
  }
  late final List<List<_PreparedSub>> pieces;
  late final List<Path> original;
  late final List<Path> letters;
}

// ---------------------------------------------------------------------------------------------
// Painter – everything is a function of time t (seconds)
// ---------------------------------------------------------------------------------------------
class _IntroPainter extends CustomPainter {
  _IntroPainter({
    required this.time,
    required this.geo,
    required this.ink,
    required this.shine,
    required this.ball,
    required this.glowInner,
    required this.glowOuter,
    required this.blurLetters,
    required this.glowFinal,
  }) : super(repaint: time);

  final ValueListenable<double> time;
  final _IntroGeometry geo;
  final Color ink, shine, ball, glowInner, glowOuter;
  final bool blurLetters;
  final double glowFinal;

  static const double _cx = 790,
      _cy = 351; // ball (top end of the C), SVG units, before the icon scale

  // TUNE ME: lockup layout (relative to the authored artwork).
  static const double kIconScale = 0.81; // the C mark, around its centre
  static const double kTextScale = 1.44; // the CONNECTUM wordmark
  static const double kGapScale = 2.0; // space between icon and name

  // Authored artwork measurements (SVG units): mark bounds and wordmark box.
  static const double _markCx = 512, _markCy = 514;
  static const double _markTop = 126.6, _markBottom = 901.5;
  static const double _wordHalfW = 227.5, _wordMidY = 19, _wordH = 37.5;

  static const double _iconTop = _markCy - (_markCy - _markTop) * kIconScale;
  static const double _iconBottom =
      _markCy + (_markBottom - _markCy) * kIconScale;
  static const double _wordScale = IntroGeo.wordScale * kTextScale;
  static const double _wordX = _markCx - _wordHalfW * _wordScale;
  static const double _wordY =
      _iconBottom + (IntroGeo.wordY - _markBottom) * kGapScale;
  static const double _wordCy = _wordY + _wordMidY * _wordScale;

  // Camera: starts on the (scaled) ball, settles on the lockup centre.
  static const double _camX0 = _markCx + (_cx - _markCx) * kIconScale;
  static const double _camY0 = _markCy + (_cy - _markCy) * kIconScale;
  static const double _endX = _markCx;
  static const double _endY = (_iconTop + _wordY + _wordH * _wordScale) / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final t = _clamp(time.value, 0, IntroTiming.duration);
    final unit = math.min(size.width, size.height) / 1200.0;
    canvas.save();
    canvas.translate(
      (size.width - 1200 * unit) / 2,
      (size.height - 1200 * unit) / 2,
    );
    canvas.scale(unit);

    // camera: starts close on the ball, pulls back and settles on the lockup
    final cp = _eInOutSine(
      _clamp((t - IntroTiming.grow0) / (IntroTiming.grow + .3)),
    );
    final s = math.exp(_lerp(math.log(1.9), math.log(0.92), cp));
    final camX = _lerp(_camX0, _endX, cp), camY = _lerp(_camY0, _endY, cp);
    canvas.translate(600, 600);
    canvas.scale(s);
    canvas.translate(-camX, -camY);

    // two soft thumps: when the C lands and when the name lands
    final b1 = math.sin(_pi * _clamp((t - (IntroTiming.grow1 - .25)) / .85));
    final b2 = math.sin(_pi * _clamp((t - (IntroTiming.last - .25)) / .8));
    final ls = 1 + 0.022 * b1 + 0.014 * b2;
    canvas.translate(_endX, _endY);
    canvas.scale(ls);
    canvas.translate(-_endX, -_endY);

    final gp = _clamp((t - IntroTiming.glintAt) / IntroTiming.glint);
    _paintGlow(canvas, t, gp);
    _paintMark(canvas, t);
    _paintWord(canvas, t, gp);

    canvas.restore();
  }

  // ---- warm bloom under the name -------------------------------------------------------------
  void _paintGlow(Canvas canvas, double t, double gp) {
    final land = _smooth(
      _clamp((t - IntroTiming.word) / (IntroTiming.last - IntroTiming.word)),
    );
    final op = _clamp(glowFinal * land + .45 * math.sin(_pi * gp));
    if (op <= 0.003) return;
    canvas.save();
    canvas.translate(_markCx, _wordCy);
    canvas.scale(470 * kTextScale, 86 * kTextScale);
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        1,
        [
          glowInner.withValues(alpha: .42 * op),
          glowOuter.withValues(alpha: .14 * op),
          glowOuter.withValues(alpha: 0),
        ],
        const [0, .55, 1],
      );
    canvas.drawCircle(Offset.zero, 1, paint);
    canvas.restore();
  }

  // ---- the logo mark --------------------------------------------------------------------------
  void _paintMark(Canvas canvas, double t) {
    final g = _clamp((t - IntroTiming.grow0) / IntroTiming.grow);
    final pop = _clamp(t / IntroTiming.pop);
    final k = _lerp(.74, 1, _eOutBack(pop));
    final markOpacity = _eOutCubic(_clamp(t / (IntroTiming.pop * .6)));

    canvas.save();
    canvas.translate(_markCx, _markCy);
    canvas.scale(kIconScale);
    canvas.translate(-_markCx, -_markCy);
    canvas.translate(_cx, _cy);
    canvas.scale(k);
    canvas.translate(-_cx, -_cy);
    final layered = markOpacity < .999;
    if (layered) {
      canvas.saveLayer(
        null,
        Paint()..color = AppColors.ink.withValues(alpha: markOpacity),
      );
    }

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    if (g >= 1) {
      // the exact original artwork
      for (int i = 0; i < geo.original.length; i++) {
        fill.color = Color(introPieces[i].color);
        canvas.drawPath(geo.original[i], fill);
      }
    } else {
      for (int i = 0; i < geo.pieces.length; i++) {
        final path = Path();
        bool any = false;
        for (final s in geo.pieces[i]) {
          final l = _clamp((g - s.src.delay) / IntroGeo.wp);
          if (l <= 0) continue; // not born yet: invisible
          any = true;
          final ea = _eInOutCubic(l);
          final er = _eOutCubic(_clamp(l * 1.1));
          final es = _eOutBack(_clamp((l - .04) / .96), .7);
          final th = s.src.th0 + (s.src.thf - s.src.th0) * ea;
          final r = s.src.r0c + (s.src.rf - s.src.r0c) * er;
          final px = IntroGeo.cx + r * math.cos(th),
              py = IntroGeo.cy + r * math.sin(th);
          final rs = s.src.rs;
          for (int j = 0; j < s.n; j++) {
            final ox = rs * s.cosA[j], oy = rs * s.sinA[j];
            final x = px + ox + (s.fx[j] - ox) * es;
            final y = py + oy + (s.fy[j] - oy) * es;
            if (j == 0) {
              path.moveTo(x, y);
            } else {
              path.lineTo(x, y);
            }
          }
          if (s.src.closed) path.close();
        }
        if (any) {
          fill.color = Color(introPieces[i].color);
          canvas.drawPath(path, fill);
        }
      }
      // the solid ball that the C grows out of fades away as the first pieces leave it
      final ballOp = 1 - _smooth(_clamp((g - .05) / .25));
      if (ballOp > .003) {
        canvas.drawCircle(
          const Offset(IntroGeo.ballX, IntroGeo.ballY),
          IntroGeo.ballR,
          Paint()..color = ball.withValues(alpha: ballOp),
        );
      }
    }
    if (layered) canvas.restore();
    canvas.restore();
  }

  // ---- wordmark -------------------------------------------------------------------------------
  void _paintWord(Canvas canvas, double t, double gp) {
    canvas.save();
    canvas.translate(_wordX, _wordY);
    canvas.scale(_wordScale);

    final showShine = gp > 0 && gp < 1;
    Shader? shineShader;
    if (showShine) {
      final gx = _lerp(-120, 520, _eInOutSine(gp));
      final k = math.tan(-18 * _pi / 180);
      final m = Float64List.fromList(<double>[
        1,
        0,
        0,
        0,
        k,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        gx,
        0,
        0,
        1,
      ]);
      shineShader = ui.Gradient.linear(
        Offset.zero,
        const Offset(80, 0),
        [
          shine.withValues(alpha: 0),
          shine.withValues(alpha: .95),
          shine.withValues(alpha: 0),
        ],
        const [0, .5, 1],
        TileMode.clamp,
        m,
      );
    }

    for (int i = 0; i < geo.letters.length; i++) {
      final lcx = introLetters[i].cx;
      final p = _clamp(
        (t - (IntroTiming.word + i * IntroTiming.stagger)) / IntroTiming.letter,
      );
      if (p <= 0) continue;
      final e = _eOutCubic(p), et = _eOutQuart(p);
      final sc = 1 + .5 * (1 - e);
      final dx = (lcx - 227.5) * .26 * (1 - et);
      final dy = 9 * (1 - e);
      final op = _eOutCubic(_clamp(p / .5));
      final blur = 9 * math.pow(1 - e, 1.6).toDouble();

      canvas.save();
      canvas.translate(lcx + dx, 19 + dy);
      canvas.scale(sc);
      canvas.translate(-lcx, -19);
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        ..color = ink.withValues(alpha: op);
      if (blurLetters && blur > .05) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      }
      canvas.drawPath(geo.letters[i], paint);
      if (shineShader != null) {
        canvas.drawPath(
          geo.letters[i],
          Paint()
            ..shader = shineShader
            ..isAntiAlias = true,
        );
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _IntroPainter old) =>
      old.ink != ink ||
      old.shine != shine ||
      old.ball != ball ||
      old.glowInner != glowInner ||
      old.glowOuter != glowOuter ||
      old.blurLetters != blurLetters ||
      old.glowFinal != glowFinal;
}
