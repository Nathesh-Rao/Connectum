import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';

/// A barely-there decoration in a card's top-right corner: a soft blue to
/// lavender radial wash inside a smooth curve, and a translucent white wave
/// offset down-left. The parent clips to its rounded rect. Nothing is painted
/// below the curve.
class CardTopRightDecoration extends StatelessWidget {
  const CardTopRightDecoration({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, c) => CustomPaint(
        size: c.biggest,
        painter: CardTopRightDecorationPainter(size: c.biggest),
      ),
    ),
  );
}

class CardTopRightDecorationPainter extends CustomPainter {
  CardTopRightDecorationPainter({
    required this.size,
    this.softBlue = AppSv.svDecoSoftBlue,
    this.paleBlue = AppSv.svDecoPaleBlue,
    this.paleLavender = AppSv.svDecoPaleLavender,
    this.white = AppSv.svDecoWhite,
  });

  final Size size;
  final Color softBlue, paleBlue, paleLavender, white;

  Size? _pathSize;
  Path? _path;

  /// Control points, normalised: start, then (c1, c2, end) per segment.
  static const _start = Offset(0.52, 0);
  static const _segments = [
    [Offset(0.56, 0.08), Offset(0.60, 0.18), Offset(0.65, 0.22)],
    [Offset(0.70, 0.28), Offset(0.74, 0.31), Offset(0.78, 0.30)],
    [Offset(0.84, 0.30), Offset(0.88, 0.26), Offset(0.90, 0.23)],
    [Offset(0.93, 0.21), Offset(0.97, 0.16), Offset(1.00, 0.12)],
  ];

  Path pathFor(Size size) {
    if (_path != null && _pathSize == size) return _path!;
    // the deepest point (0.30 h) with the curve overshoot, never goes below svDecoMaxDepth
    final h = size.height.clamp(0.0, AppSv.svDecoMaxDepth / 0.32);
    Offset p(Offset n) => Offset(n.dx * size.width, n.dy * h);
    final path = Path()..moveTo(p(_start).dx, p(_start).dy);
    for (final s in _segments) {
      path.cubicTo(
        p(s[0]).dx,
        p(s[0]).dy,
        p(s[1]).dx,
        p(s[1]).dy,
        p(s[2]).dx,
        p(s[2]).dy,
      );
    }
    path
      ..lineTo(size.width, 0)
      ..close();
    _pathSize = size;
    return _path = path;
  }

  @override
  void paint(Canvas canvas, Size paintSize) {
    final size = paintSize;
    if (size.isEmpty) return;
    final path = pathFor(size);
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..shader = RadialGradient(
          center: Alignment.topRight,
          radius: 0.6,
          colors: [
            softBlue,
            paleBlue,
            paleLavender,
            paleLavender.withValues(alpha: 0),
          ],
          stops: const [0, 0.4, 0.75, 1],
        ).createShader(bounds),
    );
    canvas.drawPath(
      path.shift(const Offset(-AppSv.svDecoWaveOffset, AppSv.svDecoWaveOffset)),
      Paint()
        ..isAntiAlias = true
        ..color = white.withValues(alpha: AppSv.svDecoWaveAlpha),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(CardTopRightDecorationPainter old) =>
      old.size != size ||
      old.softBlue != softBlue ||
      old.paleBlue != paleBlue ||
      old.paleLavender != paleLavender ||
      old.white != white;
}
