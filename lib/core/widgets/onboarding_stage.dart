import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_ambient.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// The box every onboarding illustration lives in: 340x270, scaled down (same
/// aspect) when the width or height is short, centred otherwise, on the peach
/// glow band that bleeds to the screen edges. The slides are the pages of a
/// PageView inside the box: [itemBuilder] returns the artwork of one slide.
class OnboardingStage extends StatelessWidget {
  const OnboardingStage({
    super.key,
    required this.slide,
    required this.controller,
    required this.itemCount,
    required this.onPageChanged,
    required this.itemBuilder,
  });

  final int slide;
  final PageController controller;
  final int itemCount;
  final ValueChanged<int> onPageChanged;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        var width = min(AppSpacing.stageWidth, box.maxWidth);
        var height = width * AppSpacing.stageHeight / AppSpacing.stageWidth;
        if (box.maxHeight.isFinite && height > box.maxHeight) {
          height = box.maxHeight;
          width = height * AppSpacing.stageWidth / AppSpacing.stageHeight;
        }
        final bleed = (box.maxWidth - width) / 2 + AppSpacing.page;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -bleed,
                  right: -bleed,
                  top: -AppAmbient.onboardingBandTop,
                  bottom: -AppAmbient.onboardingBandBottom,
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _BandPainter(slide)),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: PageView.builder(
                    controller: controller,
                    onPageChanged: onPageChanged,
                    itemCount: itemCount,
                    itemBuilder: itemBuilder,
                  ),
                ),
              ],
            ),
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
    _ellipse(
      canvas,
      size,
      const Offset(0.9, 0.06),
      const Offset(0.6, 0.7),
      AppColors.apricot.withValues(alpha: 0.55),
    );
    _ellipse(
      canvas,
      size,
      const Offset(0.04, 0.94),
      const Offset(0.7, 0.7),
      AppColors.peach.withValues(alpha: 0.95),
    );
    _ellipse(
      canvas,
      size,
      const Offset(0.5, 0.48),
      const Offset(0.8, 0.85),
      AppColors.ivory,
    );
    for (final s in AppAmbient.onboardingSpheres[slide.clamp(0, 2)]) {
      _sphere(
        canvas,
        Offset(s.x * size.width, s.y + AppAmbient.onboardingBandTop),
        s.size,
      );
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
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
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
            AppColors.apricot.withValues(alpha: 0.45),
            AppColors.apricot.withValues(alpha: 0),
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
            AppColors.ivory,
            AppColors.apricot,
            AppColors.apricot.withValues(alpha: 0),
          ],
          stops: const [0, 0.38, 0.72],
        ).createShader(box),
    );
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.slide != slide;
}
