import 'package:flutter/material.dart';

import '../theme/app_ambient.dart';
import '../theme/app_colors.dart';
import 'onboarding_art/onboarding_art.dart';

/// The onboarding animation slot, shared by the real onboarding and its debug
/// copy: a PageView of the three native animations (network, buildings,
/// shield) on the soft glow band. The pages are as wide as the screen (side
/// insets included), the art is capped at [maxArtWidth] and centred on wide
/// screens, keeps its aspect ratio and shrinks (never stretches) when the slot
/// is too short. Only the page for [slide] animates.
class OnboardingArtStage extends StatelessWidget {
  const OnboardingArtStage({
    super.key,
    required this.slide,
    required this.controller,
    required this.onPageChanged,
  });

  /// Page 1 conversations, page 2 enterprises, page 3 security.
  static const kinds = [
    OnboardingArtKind.network,
    OnboardingArtKind.buildings,
    OnboardingArtKind.shield,
  ];

  /// Widest the art gets on tablets, in dp.
  static const maxArtWidth = 600.0;

  /// The network page's glass orbs, mirror-symmetric about the screen centre
  /// (the half-cut one at the left edge is moved inside): x is a proportion of
  /// the width (of 390) for the left edge of the orb, then y and diameter in
  /// dp. Each is drawn together with its mirror, see [networkOrbRects].
  static const networkOrbs = [
    OnboardingSphere(274 / 390, 5, 63),
    OnboardingSphere(138 / 390, 30, 22),
    OnboardingSphere(340 / 390, 238, 16),
    OnboardingSphere(48 / 390, 202, 32),
  ];

  /// Every network orb (each with its mirror) as a rect in the band, for a
  /// screen [width] wide (x, y relative to the band's top, size).
  static List<Rect> networkOrbRects(double width) => [
    for (final s in networkOrbs) ...[
      Rect.fromLTWH(s.x * width, s.y, s.size, s.size),
      Rect.fromLTWH(width - s.x * width - s.size, s.y, s.size, s.size),
    ],
  ];

  final int slide;
  final PageController controller;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    // The screen, not the padded body: the art must reach both edges.
    final screen = MediaQueryData.fromView(View.of(context));
    return LayoutBuilder(
      builder: (context, box) {
        final height = box.maxHeight.isFinite ? box.maxHeight : 270.0;
        return SizedBox(
          width: box.maxWidth,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -screen.padding.left,
                width: screen.size.width,
                top: -AppAmbient.onboardingBandTop,
                bottom: -AppAmbient.onboardingBandBottom,
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _BandPainter(slide)),
                  ),
                ),
              ),
              Positioned(
                left: -screen.padding.left,
                width: screen.size.width,
                top: 0,
                bottom: 0,
                child: PageView.builder(
                  controller: controller,
                  onPageChanged: onPageChanged,
                  itemCount: kinds.length,
                  itemBuilder: (context, i) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: maxArtWidth),
                      child: OnboardingArt(
                        kind: kinds[i],
                        isActive: slide == i,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BandPainter extends CustomPainter {
  const _BandPainter(this.slide);

  final int slide;

  void _ellipse(
    Canvas canvas,
    Size size,
    Offset at,
    Offset radii,
    Color color,
  ) {
    canvas.save();
    canvas.translate(at.dx * size.width, at.dy * size.height);
    canvas.scale(radii.dx * size.width, radii.dy * size.height);
    canvas.drawRect(
      const Rect.fromLTRB(-3, -3, 3, 3),
      Paint()
        ..shader = RadialGradient(
          radius: 0.5,
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0, 0.72],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    canvas.clipRect(rect);
    // the network page is mirror-symmetric: every glow and orb has a mirror
    final isMirrored = slide == 0;
    for (final x in [0.9, if (isMirrored) 0.1]) {
      _ellipse(
        canvas,
        size,
        Offset(x, 0.06),
        const Offset(0.6, 0.7),
        AppColors.primaryBorder.withValues(alpha: 0.55),
      );
    }
    for (final x in [0.04, if (isMirrored) 0.96]) {
      _ellipse(
        canvas,
        size,
        Offset(x, 0.94),
        const Offset(0.7, 0.7),
        AppColors.primaryTintStrong.withValues(alpha: 0.95),
      );
    }
    _ellipse(
      canvas,
      size,
      const Offset(0.5, 0.48),
      const Offset(0.8, 0.85),
      AppColors.white,
    );
    if (isMirrored) {
      for (final r in OnboardingArtStage.networkOrbRects(size.width)) {
        _sphere(
          canvas,
          Offset(r.left, r.top + AppAmbient.onboardingBandTop),
          r.width,
        );
      }
    } else {
      for (final s in AppAmbient.onboardingSpheres[slide.clamp(0, 2)]) {
        _sphere(
          canvas,
          Offset(s.x * size.width, s.y + AppAmbient.onboardingBandTop),
          s.size,
        );
      }
    }
    // Fade the band out at the top and bottom edges.
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, 0.16, 0.7, 1],
        ).createShader(rect),
    );
    canvas.restore();
  }

  // A glow (the prototype's box-shadow) under a soft sphere, without a blur.
  void _sphere(Canvas canvas, Offset topLeft, double diameter) {
    final center = topLeft + Offset(diameter / 2, diameter / 2);
    final glowRadius = diameter / 2 + 19;
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.primaryBorder.withValues(alpha: 0.45),
            AppColors.primaryBorder.withValues(alpha: 0),
          ],
          stops: [(diameter / 2 - 6) / glowRadius, 1],
        ).createShader(Rect.fromCircle(center: center, radius: glowRadius)),
    );
    final box = Rect.fromCircle(center: center, radius: diameter / 2);
    canvas.drawCircle(
      center,
      diameter / 2,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.32, -0.4),
          radius: 0.96,
          colors: [
            AppColors.white,
            AppColors.primaryBorder,
            AppColors.primaryBorder.withValues(alpha: 0),
          ],
          stops: const [0, 0.38, 0.72],
        ).createShader(box),
    );
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.slide != slide;
}
