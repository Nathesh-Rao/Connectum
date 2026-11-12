import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

// TUNE ME: bubble surface of the primary buttons and FABs. Edit the numbers,
// then hot restart. Static, painted once per size/state; no animation.

/// Base fill under the discs.
const kBubbleBase = AppColors.primary;

/// Multiplies every disc opacity (0 = flat button, 1 = as listed).
const kBubbleOpacityScale = 1.0;

/// Where the glossy highlight sits inside each disc, as an Alignment
/// (-1..1; negative = top-left), and how much of the disc opacity is left at
/// the far edge (0..1).
const kBubbleHighlight = Alignment(-0.35, -0.4);
const kBubbleEdgeFalloff = 0.35;

/// 1 px inner highlight along the top edge, and the darker pressed overlay.
const kBubbleTopHighlightOpacity = 0.12;
const kBubblePressedColor = AppColors.primaryStrong;
const kBubblePressedOpacity = 0.28;

/// The centre band of the surface that must stay calm under the label: this
/// fraction of the width on each side of the middle, and of the height around
/// the middle. The contrast test looks at the discs that reach it.
const kBubbleLabelBandX = 0.2;
const kBubbleLabelBandY = 0.2;

/// Width tiers (px): wide from [kBubbleWideFrom], medium from
/// [kBubbleMediumFrom], else narrow.
const kBubbleWideFrom = 280.0;
const kBubbleMediumFrom = 160.0;

/// One disc: centre as fractions of the width ([dx]) and height ([dy]),
/// diameter as a multiple of the height, colour and opacity (before
/// [kBubbleOpacityScale]). Listed in paint order (later is on top).
class BubbleDisc {
  const BubbleDisc(this.dx, this.dy, this.diameter, this.color, this.opacity);

  final double dx;
  final double dy;
  final double diameter;
  final Color color;
  final double opacity;
}

const _strong = AppColors.primaryStrong;
const _bright = AppColors.primaryBright;
const _light = AppColors.primaryLight;
const _cyan = AppColors.cyanBlue;

/// Wide buttons (>= 280 px): 7 discs, bigger ones at both ends, one very
/// faint small disc near the middle.
const kBubblesWide = <BubbleDisc>[
  BubbleDisc(0.02, 0.85, 1.10, _strong, 0.30),
  BubbleDisc(0.08, 0.20, 0.80, _bright, 0.24),
  BubbleDisc(0.17, 0.72, 0.55, _cyan, 0.16),
  BubbleDisc(0.50, 0.85, 0.45, _light, 0.08),
  BubbleDisc(0.84, 0.15, 1.00, _strong, 0.28),
  BubbleDisc(0.92, 0.80, 0.75, _bright, 0.26),
  BubbleDisc(0.76, 0.62, 0.50, _light, 0.14),
];

/// Medium buttons (160 to 280 px): 5 discs.
const kBubblesMedium = <BubbleDisc>[
  BubbleDisc(0.03, 0.85, 1.10, _strong, 0.30),
  BubbleDisc(0.10, 0.20, 0.75, _bright, 0.24),
  BubbleDisc(0.52, 0.92, 0.45, _light, 0.08),
  BubbleDisc(0.92, 0.15, 1.00, _strong, 0.28),
  BubbleDisc(0.90, 0.85, 0.70, _cyan, 0.18),
];

/// Narrow buttons (< 160 px) and the extended FAB: 3 discs.
const kBubblesNarrow = <BubbleDisc>[
  BubbleDisc(0.00, 0.80, 1.00, _strong, 0.30),
  BubbleDisc(0.12, 0.15, 0.50, _cyan, 0.16),
  BubbleDisc(1.00, 0.20, 0.95, _bright, 0.26),
];

/// Circle FAB: 3 discs.
const kBubblesFab = <BubbleDisc>[
  BubbleDisc(0.15, 0.85, 0.90, _strong, 0.30),
  BubbleDisc(0.85, 0.15, 0.85, _bright, 0.26),
  BubbleDisc(0.80, 0.90, 0.50, _cyan, 0.16),
];

/// The discs for a surface of [size]. [isFab] picks the FAB sets: the circle
/// FAB (about square) or, when wider, the narrow button set.
List<BubbleDisc> bubbleDiscsFor(Size size, {bool isFab = false}) {
  if (isFab && size.width / size.height < 1.3) return kBubblesFab;
  if (size.width >= kBubbleWideFrom) return kBubblesWide;
  if (size.width >= kBubbleMediumFrom) return kBubblesMedium;
  return kBubblesNarrow;
}

/// The lightest colour the discs can reach in the label band of a surface of
/// [size]: the base with every disc that reaches the band and is lighter than
/// the base, each at its full opacity (darker discs only lower it). The
/// contrast test checks white on this.
Color bubbleLightestStack(Size size, {bool isFab = false}) {
  final band = Rect.fromLTRB(
    size.width * (0.5 - kBubbleLabelBandX),
    size.height * (0.5 - kBubbleLabelBandY),
    size.width * (0.5 + kBubbleLabelBandX),
    size.height * (0.5 + kBubbleLabelBandY),
  );
  final baseLuminance = kBubbleBase.computeLuminance();
  var out = kBubbleBase;
  for (final d in bubbleDiscsFor(size, isFab: isFab)) {
    if (d.color.computeLuminance() <= baseLuminance) continue;
    final centre = Offset(d.dx * size.width, d.dy * size.height);
    final nearest = Offset(
      centre.dx.clamp(band.left, band.right),
      centre.dy.clamp(band.top, band.bottom),
    );
    if ((centre - nearest).distance >= d.diameter * size.height / 2) continue;
    out = Color.alphaBlend(
      d.color.withValues(alpha: d.opacity * kBubbleOpacityScale),
      out,
    );
  }
  return out;
}

/// A filled surface of [kBubbleBase] with separate glossy round discs,
/// clipped to [borderRadius]. A disabled surface is flat
/// [AppColors.primaryDisabled]. Put the content in [child]; [boxShadow]
/// raises it. [isFab] selects the FAB disc sets.
class AppBubbleSurface extends StatelessWidget {
  const AppBubbleSurface({
    super.key,
    required this.borderRadius,
    required this.child,
    this.isEnabled = true,
    this.isPressed = false,
    this.isFab = false,
    this.boxShadow,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final bool isEnabled;
  final bool isPressed;
  final bool isFab;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: isEnabled ? boxShadow : null,
      ),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BubblePainter(borderRadius, isEnabled, isPressed, isFab),
          child: child,
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter(
    this.borderRadius,
    this.isEnabled,
    this.isPressed,
    this.isFab,
  );

  final BorderRadius borderRadius;
  final bool isEnabled;
  final bool isPressed;
  final bool isFab;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shape = borderRadius.resolve(TextDirection.ltr).toRRect(rect);
    canvas.save();
    canvas.clipRRect(shape);
    if (!isEnabled) {
      canvas.drawRect(rect, Paint()..color = AppColors.primaryDisabled);
      canvas.restore();
      return;
    }
    canvas.drawRect(rect, Paint()..color = kBubbleBase);

    for (final d in bubbleDiscsFor(size, isFab: isFab)) {
      final alpha = math.min(1.0, d.opacity * kBubbleOpacityScale);
      final centre = Offset(d.dx * size.width, d.dy * size.height);
      final circle = Rect.fromCircle(
        center: centre,
        radius: d.diameter * size.height / 2,
      );
      canvas.drawCircle(
        centre,
        circle.width / 2,
        Paint()
          ..shader = RadialGradient(
            center: kBubbleHighlight,
            radius: 0.95,
            colors: [
              d.color.withValues(alpha: alpha),
              d.color.withValues(alpha: alpha * kBubbleEdgeFalloff),
            ],
          ).createShader(circle),
      );
    }

    canvas.drawRRect(
      shape.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.white.withValues(alpha: kBubbleTopHighlightOpacity),
            AppColors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.35],
        ).createShader(rect),
    );
    if (isPressed) {
      canvas.drawRect(
        rect,
        Paint()
          ..color = kBubblePressedColor.withValues(
            alpha: kBubblePressedOpacity,
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.borderRadius != borderRadius ||
      old.isEnabled != isEnabled ||
      old.isPressed != isPressed ||
      old.isFab != isFab;
}
