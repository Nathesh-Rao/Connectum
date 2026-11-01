import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';

/// Four corner brackets around the scanning square, plus the sweeping line
/// while the camera is live. The brackets turn green once a code is accepted.
class ViewfinderOverlay extends StatelessWidget {
  const ViewfinderOverlay({
    super.key,
    required this.isScanning,
    required this.isSuccess,
  });

  final bool isScanning;
  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    final isAnimated = !MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.viewfinderInset),
      child: Stack(
        fit: StackFit.expand,
        children: [
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(
              end: isSuccess ? AppColors.yesDot : AppColors.background,
            ),
            duration: AppDurations.scanSuccess,
            builder: (_, color, _) => CustomPaint(
              painter: _BracketPainter(color ?? AppColors.background),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.scanLineInset),
            child: ScanLine(isActive: isScanning && !isSuccess && isAnimated),
          ),
        ],
      ),
    );
  }
}

class ScanLine extends StatefulWidget {
  const ScanLine({super.key, required this.isActive});

  final bool isActive;

  @override
  State<ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<ScanLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.scanSweep,
  );
  late final Animation<double> _position = CurvedAnimation(
    parent: _controller,
    curve: AppCurves.inOut,
  );

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(ScanLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive == oldWidget.isActive) return;
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return const SizedBox.shrink();
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _position,
        builder: (_, _) => CustomPaint(
          size: Size.infinite,
          painter: _LinePainter(_position.value),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const h = AppSpacing.scanLineHeight;
    final y = (size.height - h) * t;
    Shader fade(double alpha) => LinearGradient(
      colors: [
        AppColors.accent.withValues(alpha: 0),
        AppColors.accent.withValues(alpha: alpha),
        AppColors.accent.withValues(alpha: alpha),
        AppColors.accent.withValues(alpha: 0),
      ],
      stops: const [0, 0.2, 0.8, 1],
    ).createShader(Rect.fromLTWH(0, y, size.width, h));
    final glow = Rect.fromLTWH(0, y - h * 2, size.width, h * 5);
    canvas.drawRect(
      glow,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.accent.withValues(alpha: 0),
            AppColors.accent.withValues(alpha: 0.14),
            AppColors.accent.withValues(alpha: 0),
          ],
        ).createShader(glow),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y, size.width, h),
        const Radius.circular(h / 2),
      ),
      Paint()..shader = fade(0.7),
    );
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) => oldDelegate.t != t;
}

class _BracketPainter extends CustomPainter {
  const _BracketPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppSpacing.bracketStroke
      ..strokeCap = StrokeCap.round;
    const l = AppSpacing.bracketLength;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, l)
      ..lineTo(0, 0)
      ..lineTo(l, 0)
      ..moveTo(w - l, 0)
      ..lineTo(w, 0)
      ..lineTo(w, l)
      ..moveTo(w, h - l)
      ..lineTo(w, h)
      ..lineTo(w - l, h)
      ..moveTo(l, h)
      ..lineTo(0, h)
      ..lineTo(0, h - l);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BracketPainter oldDelegate) =>
      oldDelegate.color != color;
}
