import 'package:flutter/material.dart';

import '../theme/app_ambient.dart';
import '../theme/app_colors.dart';

enum AppAmbientVariant { access, splash }

/// The soft blue disc, thin orbits (the outer one violet) and small spheres behind the splash,
/// authentication and verification screens. Static, no blur.
class AppAmbientBackdrop extends StatelessWidget {
  const AppAmbientBackdrop({super.key, required this.variant});

  final AppAmbientVariant variant;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _AmbientPainter(variant, MediaQuery.paddingOf(context).top),
        ),
      ),
    );
  }
}

Color _fade(Color color, double opacity) =>
    color.withValues(alpha: color.a * opacity);

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter(this.variant, this.topInset);

  final AppAmbientVariant variant;
  final double topInset;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height - topInset;
    Rect box(AppAmbientShape s) => Rect.fromLTWH(
      s.x * width,
      topInset + s.y * height,
      s.size * width,
      s.size * width,
    );

    if (variant == AppAmbientVariant.splash) {
      _disc(canvas, box(AppAmbient.splashDisc), AppAmbient.splashDisc.opacity);
      _orbit(
        canvas,
        box(AppAmbient.splashOrbit),
        AppColors.ambientOrbitViolet,
        AppAmbient.splashOrbit.opacity,
      );
      _orbit(
        canvas,
        box(AppAmbient.splashOrbitInner),
        AppColors.ambientOrbitInner,
        AppAmbient.splashOrbitInner.opacity,
      );
      return;
    }
    _disc(canvas, box(AppAmbient.accessDisc), 1);
    _orbit(
      canvas,
      box(AppAmbient.accessOrbit),
      AppColors.ambientOrbitViolet,
      1,
    );
    final inner = box(AppAmbient.accessOrbitInner);
    _orbit(
      canvas,
      Rect.fromCenter(
        center: box(AppAmbient.accessOrbit).center,
        width: inner.width,
        height: inner.height,
      ),
      AppColors.ambientOrbitInner,
      1,
    );
    for (final sphere in AppAmbient.accessSpheres) {
      _sphere(canvas, box(sphere), sphere.opacity);
    }
  }

  // radial-gradient(circle at 28% 65%, centre, edge 65%, transparent 72%),
  // measured to the farthest corner (0.97 of the box).
  void _disc(Canvas canvas, Rect rect, double opacity) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.44, 0.3),
        radius: 0.97,
        colors: [
          _fade(AppColors.ambientDiscCenter, opacity),
          _fade(AppColors.ambientDiscEdge, opacity),
          const Color(0x00000000),
        ],
        stops: const [0, 0.65, 0.72],
      ).createShader(rect);
    canvas.drawCircle(rect.center, rect.width / 2, paint);
  }

  void _orbit(Canvas canvas, Rect rect, Color color, double opacity) {
    canvas.drawCircle(
      rect.center,
      rect.width / 2 - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _fade(color, opacity),
    );
  }

  // radial-gradient(circle at 30% 27%, highlight 0, mid 38%, accent 85%).
  void _sphere(Canvas canvas, Rect rect, double opacity) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.46),
        radius: 1.01,
        colors: [
          _fade(AppColors.sphereHighlight, opacity),
          _fade(AppColors.sphereMid, opacity),
          _fade(AppColors.primaryBright, opacity),
        ],
        stops: const [0, 0.38, 0.85],
      ).createShader(rect);
    canvas.drawCircle(rect.center, rect.width / 2, paint);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.variant != variant || old.topInset != topInset;
}
