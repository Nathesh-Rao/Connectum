import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../crop_math.dart';
import '../photo_renderer.dart';

/// The picture under a fixed square frame with a round window: what is
/// outside the circle is dimmed, because the avatar is a circle. A thirds grid
/// shows while the picture is moved.
class CropStage extends StatelessWidget {
  const CropStage({
    super.key,
    required this.photo,
    required this.state,
    required this.isMoving,
  });

  static const dimAlpha = 0.58;
  static const ringAlpha = 0.9;
  static const ringWidth = 1.5;
  static const gridAlpha = 0.55;
  static const gridWidth = 1.0;

  final ui.Image photo;
  final CropState state;
  final bool isMoving;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _CropPainter(photo, state, isMoving),
    size: Size.square(state.box),
  );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.photo, this.state, this.isMoving);

  final ui.Image photo;
  final CropState state;
  final bool isMoving;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Offset.zero & size;
    canvas.save();
    canvas.clipRect(frame);
    PhotoRenderer.paint(canvas, photo, state, size.width);
    canvas.restore();

    final window = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(frame)
      ..addOval(frame);
    canvas.drawPath(
      window,
      Paint()..color = AppColors.ink.withValues(alpha: CropStage.dimAlpha),
    );
    canvas.drawOval(
      frame.deflate(CropStage.ringWidth / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = CropStage.ringWidth
        ..color = AppColors.white.withValues(alpha: CropStage.ringAlpha),
    );
    if (isMoving) {
      final line = Paint()
        ..strokeWidth = CropStage.gridWidth
        ..color = AppColors.white.withValues(alpha: CropStage.gridAlpha);
      for (var i = 1; i < 3; i++) {
        final t = size.width * i / 3;
        canvas.drawLine(Offset(t, 0), Offset(t, size.height), line);
        canvas.drawLine(Offset(0, t), Offset(size.width, t), line);
      }
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.state != state || old.photo != photo || old.isMoving != isMoving;
}
