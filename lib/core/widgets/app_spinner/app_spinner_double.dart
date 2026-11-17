import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_spacing.dart';
import '../onboarding_art/svg_path_parser.dart';
import 'generated/spinner_double_data.dart';
import 'pull_refresh_config.dart';
import 'spinner_path_data.dart';

/// The two-arc spinner of `assets/icons/loader/spinner-double.svg`, ported
/// from its SMIL animation: the thick arc turns clockwise in 0.8 s, the thin
/// arc counter-clockwise in 0.6 s, both around the centre.
///
/// While [spinning] is false the arcs follow [progress] (one turn over a full
/// pull) and the spinner scales 0.6 to 1 and fades in. While [spinning] it
/// turns freely from real elapsed time. Reduced motion keeps a static frame.
class AppSpinnerDouble extends StatefulWidget {
  const AppSpinnerDouble({
    super.key,
    this.size = AppSpacing.spinnerPull,
    this.color = kPullRefreshColor,
    this.progress = 1,
    this.spinning = true,
  });

  final double size;
  final Color color;
  final double progress;
  final bool spinning;

  @override
  State<AppSpinnerDouble> createState() => _AppSpinnerDoubleState();
}

class _AppSpinnerDoubleState extends State<AppSpinnerDouble>
    with SingleTickerProviderStateMixin {
  final _seconds = ValueNotifier<double>(0);
  late final Ticker _ticker;
  bool _isReduced = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(
      (elapsed) => _seconds.value = elapsed.inMicroseconds / 1e6,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isReduced = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(AppSpinnerDouble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final shouldRun = widget.spinning && !_isReduced && widget.progress > 0;
    if (shouldRun && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
      _seconds.value = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress.clamp(0.0, 1.0);
    if (p <= 0) return SizedBox.square(dimension: widget.size);
    final isFree = widget.spinning && !_isReduced;
    final color = widget.color.withValues(alpha: widget.color.a * p);
    return Semantics(
      label: 'Loading',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: SpinnerDoublePainter(
              seconds: _seconds,
              isFree: isFree,
              progress: p,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpinnerShapes {
  _SpinnerShapes._();

  static final List<Path> paths = [
    for (final p in spinnerDoublePaths) parseSvgPath(p.d).path,
  ];
}

/// Draws both arcs. [seconds] is the elapsed time while free-running; when
/// [isFree] is false the angle comes from [progress].
class SpinnerDoublePainter extends CustomPainter {
  SpinnerDoublePainter({
    required ValueListenable<double> seconds,
    required this.isFree,
    required this.progress,
    required this.color,
  }) : _seconds = seconds,
       _paint = Paint()
         ..style = PaintingStyle.fill
         ..isAntiAlias = true
         ..color = color,
       super(repaint: seconds);

  final ValueListenable<double> _seconds;
  final bool isFree;
  final double progress;
  final Color color;
  final Paint _paint;

  /// The angle in radians of path [index] at [t] seconds, or at [progress]
  /// of a pull when not [isFree].
  static double angleOf(
    SpinnerPathData data, {
    required bool isFree,
    required double t,
    required double progress,
  }) {
    final turns = isFree ? t / data.durationSeconds : progress;
    return data.direction * 2 * math.pi * turns;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale =
        size.shortestSide / spinnerDoubleViewBoxWidth * (0.6 + 0.4 * progress);
    final cx = size.width / 2;
    final cy = size.height / 2;
    final t = _seconds.value;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale);
    canvas.translate(
      -(spinnerDoubleViewBoxX + spinnerDoubleViewBoxWidth / 2),
      -(spinnerDoubleViewBoxY + spinnerDoubleViewBoxHeight / 2),
    );
    for (var i = 0; i < spinnerDoublePaths.length; i++) {
      final data = spinnerDoublePaths[i];
      canvas.save();
      canvas.translate(data.pivotX, data.pivotY);
      canvas.rotate(angleOf(data, isFree: isFree, t: t, progress: progress));
      canvas.translate(-data.pivotX, -data.pivotY);
      canvas.drawPath(_SpinnerShapes.paths[i], _paint);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SpinnerDoublePainter old) =>
      old.isFree != isFree || old.progress != progress || old.color != color;
}
