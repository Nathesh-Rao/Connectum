import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The auth screens' soft discs, thin rings and small spheres (same colours as
/// [AppAmbientBackdrop]) scaled down for a card: a few shapes near three
/// corners, sized from the card width. Plain canvas work, no blur, so a
/// widget-to-image render matches the screen. Paints behind [child].
class AppCardCircles extends StatelessWidget {
  const AppCardCircles({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: const _CardCirclesPainter(), child: child);
  }
}

class _CardCirclesPainter extends CustomPainter {
  const _CardCirclesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final disc = Paint()..color = AppColors.ambientDiscCenter;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.ambientOrbitOuter;
    final ringInner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.ambientOrbitInner;

    // Top right: a disc with a ring around it.
    final topRight = Offset(w * 0.96, 0);
    canvas.drawCircle(topRight, w * 0.13, disc);
    canvas.drawCircle(topRight, w * 0.17, ring);

    // Bottom left: a ring pair around a smaller disc.
    final bottomLeft = Offset(w * 0.02, size.height);
    canvas.drawCircle(bottomLeft, w * 0.1, disc);
    canvas.drawCircle(bottomLeft, w * 0.15, ring);
    canvas.drawCircle(bottomLeft, w * 0.18, ringInner);

    // Top left and bottom right: one small sphere each.
    _sphere(canvas, Offset(w * 0.07, w * 0.06), w * 0.014, 0.6);
    _sphere(canvas, Offset(w * 0.93, size.height - w * 0.07), w * 0.02, 0.5);
  }

  void _sphere(Canvas canvas, Offset center, double radius, double opacity) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    Color fade(Color c) => c.withValues(alpha: c.a * opacity);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.46),
          radius: 1.01,
          colors: [
            fade(AppColors.sphereHighlight),
            fade(AppColors.sphereMid),
            fade(AppColors.primaryBright),
          ],
          stops: const [0, 0.38, 0.85],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_CardCirclesPainter oldDelegate) => false;
}
