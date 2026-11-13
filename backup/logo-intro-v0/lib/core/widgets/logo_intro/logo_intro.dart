import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'logo_intro_data.dart';

// TUNE ME: logo intro. All times in ms. The geometry (start order, seeds, head
// circle) comes from logo_intro_data.dart (tool/logo/generate_logo_intro_data.py).
const double kLogoIntroWidth = 240; // dp; the default width of LogoIntro
const double kLogoIntroTotalMs = 3300; // then the final frame is held
const double kLogoIntroPopEnd = 250; // head circle pop-in
const double kLogoIntroMoveA =
    250; // head moves from the centre to the top lobe
const double kLogoIntroMoveB = 1050;
const double kLogoIntroFadeA = 1000; // head starts fading
const double kLogoIntroFade = 300;
const double kLogoIntroGrowA = 550; // first C part starts
const double kLogoIntroGrowSpan = 1000; // start times spread over this span
const double kLogoIntroPartDur = 520; // one part's grow time
const double kLogoIntroPause = 150; // between the last part and the wordmark
const double kLogoIntroTextDur = 650;
const double kLogoIntroSeedBehind = 24; // degrees, seed behind a part (non-big)
const double kLogoIntroHeadBow = 22; // sideways bow of the head's path
const double kLogoIntroHeadStartScale = 0.8; // start radius / end radius
const double kLogoIntroHeadBackOut = 1.4;
const double kLogoIntroPartBackOut = 1.15;
const double kLogoIntroTextBackOut = 0.7;
const double kLogoIntroTextRise = 115; // wordmark starts this far above
const double kLogoIntroTopS = 0.10; // parts with s below this follow the head
const double kLogoIntroGrowEnd =
    kLogoIntroGrowA + kLogoIntroGrowSpan + kLogoIntroPartDur;
const double kLogoIntroTextA = kLogoIntroGrowEnd + kLogoIntroPause;

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

double _easeInOutCubic(double t) =>
    t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

double _backOut(double t, double c) {
  final p = t - 1;
  return 1 + (c + 1) * p * p * p + c * p * p;
}

/// One part's pose at a time. Reused between parts, so a frame allocates nothing.
class LogoIntroPose {
  bool isVisible = false;
  double x = 0, y = 0, along = 1, perp = 1, angle = 0, opacity = 0;
  bool isDone = false;

  /// True when the part sits at its place with no transform.
  bool get isIdentity => isDone;
}

class LogoIntroHead {
  double x = 0, y = 0, radius = 0, opacity = 0;
}

/// The timeline: pure maths from the generated data, shared by the painter and the tests.
class LogoIntroTimeline {
  LogoIntroTimeline() {
    for (var i = 0; i < logoIntroParts.length; i++) {
      final p = logoIntroParts[i];
      starts[i] = kLogoIntroGrowA + p.s * kLogoIntroGrowSpan;
    }
    final head = LogoIntroHead();
    for (var i = 0; i < logoIntroParts.length; i++) {
      final p = logoIntroParts[i];
      if (p.seedX != null && p.seedY != null && !p.isTop) {
        seedX[i] = p.seedX!;
        seedY[i] = p.seedY!;
      } else {
        headAt(starts[i], head);
        seedX[i] = head.x;
        seedY[i] = head.y;
      }
    }
  }

  final starts = List<double>.filled(logoIntroParts.length, 0);
  final seedX = List<double>.filled(logoIntroParts.length, 0);
  final seedY = List<double>.filled(logoIntroParts.length, 0);

  static const _r = logoIntroHeadRadius;

  void headAt(double t, LogoIntroHead out) {
    const dx = logoIntroHeadX - logoIntroCenterX;
    const dy = logoIntroHeadY - logoIntroCenterY;
    final len = math.sqrt(dx * dx + dy * dy);
    final e = _easeInOutCubic(
      _clamp01((t - kLogoIntroMoveA) / (kLogoIntroMoveB - kLogoIntroMoveA)),
    );
    final bow = kLogoIntroHeadBow * math.sin(math.pi * e);
    out.x = logoIntroCenterX + dx * e + (-dy / len) * bow;
    out.y = logoIntroCenterY + dy * e + (dx / len) * bow;
    const r0 = _r * kLogoIntroHeadStartScale;
    out.radius =
        (r0 + (_r - r0) * e) *
        _backOut(_clamp01(t / kLogoIntroPopEnd), kLogoIntroHeadBackOut);
    out.opacity = t <= 0
        ? 0
        : (t < kLogoIntroFadeA
              ? 1
              : _clamp01(1 - (t - kLogoIntroFadeA) / kLogoIntroFade));
  }

  void poseAt(int i, double t, LogoIntroPose out) {
    final p = logoIntroParts[i];
    final u = _clamp01((t - starts[i]) / kLogoIntroPartDur);
    out.isVisible = u > 0;
    out.isDone = u >= 1;
    if (u <= 0) return;
    if (u >= 1) {
      out
        ..x = p.focusX
        ..y = p.focusY
        ..along = 1
        ..perp = 1
        ..angle = 0
        ..opacity = 1;
      return;
    }
    final fx = p.focusX, fy = p.focusY;
    final sx = seedX[i], sy = seedY[i];
    final m = _backOut(u, kLogoIntroPartBackOut);
    final bump = math.sin(math.pi * math.min(1.25 * u, 1));
    final dist = math.sqrt((fx - sx) * (fx - sx) + (fy - sy) * (fy - sy));
    final dim = math.max(p.right - p.left, p.bottom - p.top);
    final k = (dist / dim).clamp(0.08, 0.4);
    final base = 0.22 + 0.78 * m;
    out
      ..x = sx + (fx - sx) * m
      ..y = sy + (fy - sy) * m
      ..along = base * (1 + 1.3 * k * bump)
      ..perp = base * (1 - 0.3 * k * bump)
      ..angle = math.atan2(fy - sy, fx - sx)
      ..opacity = _clamp01(4 * u);
  }

  /// Wordmark transform: translate, uniform scale and opacity.
  void textAt(double t, LogoIntroPose out) {
    final uT = _clamp01((t - kLogoIntroTextA) / kLogoIntroTextDur);
    final mt = _backOut(uT, kLogoIntroTextBackOut);
    out.isVisible = uT > 0;
    out.isDone = uT >= 1;
    out
      ..x = logoIntroTextCenterX
      ..y = logoIntroTextCenterY - (uT >= 1 ? 0 : kLogoIntroTextRise * (1 - mt))
      ..along = uT >= 1 ? 1 : 0.5 + 0.5 * mt
      ..perp = out.along
      ..angle = 0
      ..opacity = uT >= 1 ? 1 : _clamp01(2.2 * uT);
  }
}

/// Paths in the SVG's own coordinates, built once for the whole app.
class LogoIntroPaths {
  LogoIntroPaths._() {
    for (final p in logoIntroParts) {
      parts.add(_build(p.ops));
    }
    text = _build(logoIntroTextOps);
  }

  static final LogoIntroPaths instance = LogoIntroPaths._();

  final parts = <ui.Path>[];
  late final ui.Path text;

  static ui.Path _build(List<double> o) {
    final path = ui.Path();
    var i = 0;
    while (i < o.length) {
      switch (o[i++].toInt()) {
        case 0:
          path.moveTo(o[i], o[i + 1]);
          i += 2;
        case 1:
          path.lineTo(o[i], o[i + 1]);
          i += 2;
        case 2:
          path.cubicTo(o[i], o[i + 1], o[i + 2], o[i + 3], o[i + 4], o[i + 5]);
          i += 6;
        case 3:
          path.quadraticBezierTo(o[i], o[i + 1], o[i + 2], o[i + 3]);
          i += 4;
        default:
          path.close();
      }
    }
    return path;
  }
}

/// Paints the intro at [time] (ms). Order: wordmark, C parts, head circle.
class LogoIntroPainter extends CustomPainter {
  LogoIntroPainter({
    required this.time,
    required this.textColor,
    this.isLabelled = false,
  }) : super(repaint: time);

  final ValueListenable<double> time;
  final Color textColor;

  /// Debug: print each part's `s` value on it.
  final bool isLabelled;

  static final _timeline = LogoIntroTimeline();
  static final _pose = LogoIntroPose();
  static final _head = LogoIntroHead();
  static final _paint = Paint()..isAntiAlias = true;
  static final _headPaint = Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.radial(
      const Offset(-0.32, -0.4),
      1.5,
      const [
        AppColors.primaryLight,
        AppColors.primaryBright,
        AppColors.primaryBright,
      ],
      const [0, 0.55, 1],
    );

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final paths = LogoIntroPaths.instance;
    canvas.save();
    canvas.scale(size.width / logoIntroWidth);

    final tl = _timeline, pose = _pose;
    tl.textAt(t, pose);
    if (pose.isVisible) {
      _paint.color = textColor.withValues(alpha: pose.opacity * textColor.a);
      if (pose.isDone) {
        canvas.drawPath(paths.text, _paint);
      } else {
        canvas.save();
        canvas.translate(pose.x, pose.y);
        canvas.scale(pose.along, pose.perp);
        canvas.translate(-logoIntroTextCenterX, -logoIntroTextCenterY);
        canvas.drawPath(paths.text, _paint);
        canvas.restore();
      }
    }

    for (var i = 0; i < logoIntroParts.length; i++) {
      final p = logoIntroParts[i];
      tl.poseAt(i, t, pose);
      if (!pose.isVisible) continue;
      _paint.color = Color(p.fill).withValues(alpha: pose.opacity);
      if (pose.isDone) {
        canvas.drawPath(paths.parts[i], _paint);
      } else {
        canvas.save();
        canvas.translate(pose.x, pose.y);
        canvas.rotate(pose.angle);
        canvas.scale(pose.along, pose.perp);
        canvas.rotate(-pose.angle);
        canvas.translate(-p.focusX, -p.focusY);
        canvas.drawPath(paths.parts[i], _paint);
        canvas.restore();
      }
    }

    tl.headAt(t, _head);
    if (_head.opacity > 0 && _head.radius > 0) {
      _headPaint.color = Color.fromRGBO(0, 0, 0, _head.opacity);
      canvas.save();
      canvas.translate(_head.x, _head.y);
      canvas.scale(_head.radius);
      canvas.drawCircle(Offset.zero, 1, _headPaint);
      canvas.restore();
    }

    if (isLabelled) _paintLabels(canvas);
    canvas.restore();
  }

  void _paintLabels(Canvas canvas) {
    for (var i = 0; i < logoIntroParts.length; i++) {
      final p = logoIntroParts[i];
      final tp = TextPainter(
        text: TextSpan(
          text: p.s.toStringAsFixed(2),
          style: const TextStyle(
            color: AppColors.error,
            fontSize: 7,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(p.focusX - tp.width / 2, p.focusY - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(LogoIntroPainter old) =>
      old.time != time ||
      old.textColor != textColor ||
      old.isLabelled != isLabelled;
}

/// A frame of the intro at a given time; no animation of its own.
class LogoIntroFrame extends StatelessWidget {
  const LogoIntroFrame({
    super.key,
    required this.time,
    this.width = kLogoIntroWidth,
    this.textColor = AppColors.ink,
    this.isLabelled = false,
  });

  final ValueListenable<double> time;
  final double width;
  final Color textColor;
  final bool isLabelled;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(width, width * logoIntroHeight / logoIntroWidth),
        painter: LogoIntroPainter(
          time: time,
          textColor: textColor,
          isLabelled: isLabelled,
        ),
      ),
    );
  }
}

/// The logo intro: plays once at 1x, then holds the final frame. With reduced
/// motion it shows the final frame at once.
class LogoIntro extends StatefulWidget {
  const LogoIntro({
    super.key,
    this.width = kLogoIntroWidth,
    this.onCompleted,
    this.textColor = AppColors.ink,
    this.autoplay = true,
  });

  final double width;
  final VoidCallback? onCompleted;
  final Color textColor;
  final bool autoplay;

  @override
  State<LogoIntro> createState() => _LogoIntroState();
}

class _LogoIntroState extends State<LogoIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _time = ValueNotifier<double>(0);
  bool _isCompleted = false;
  bool _isStarted = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 3300), // = kLogoIntroTotalMs
        )..addListener(() {
          _time.value = _controller.value * kLogoIntroTotalMs;
        });
    _controller.addStatusListener((s) {
      if (s == AnimationStatus.completed) _complete();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isStarted || !widget.autoplay) return;
    _isStarted = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _time.value = kLogoIntroTotalMs;
      WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
    } else {
      _controller.forward();
    }
  }

  void _complete() {
    if (_isCompleted || !mounted) return;
    _isCompleted = true;
    widget.onCompleted?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LogoIntroFrame(
      time: _time,
      width: widget.width,
      textColor: widget.textColor,
    );
  }
}
