import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/theme/app_colors.dart';

enum SamplePhoto {
  landscape('Landscape 1800 x 1000', 1800, 1000),
  portrait('Portrait 1000 x 1800', 1000, 1800),
  large('Large 4000 x 3000', 4000, 3000);

  const SamplePhoto(this.label, this.width, this.height);

  final String label;
  final int width;
  final int height;
}

/// Pictures drawn in code (no real people): a gradient with a circle, a
/// stripe and corner squares, so a crop, a turn and a zoom are easy to read.
class SamplePhotos {
  SamplePhotos._();

  static Future<Uint8List> png(SamplePhoto sample) async {
    final w = sample.width.toDouble(), h = sample.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), [
          AppColors.primaryLight,
          AppColors.violet,
        ]),
    );
    final unit = (w < h ? w : h) / 10;
    canvas.drawCircle(
      Offset(w / 2, h / 2),
      unit * 2.4,
      Paint()..color = AppColors.white.withValues(alpha: 0.85),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h / 2 - unit / 4, w, unit / 2),
      Paint()..color = AppColors.ink.withValues(alpha: 0.35),
    );
    final corners = [
      (Offset.zero, AppColors.error),
      (Offset(w - unit, 0), AppColors.yesDot),
      (Offset(0, h - unit), AppColors.ink),
      (Offset(w - unit, h - unit), AppColors.white),
    ];
    for (final (at, color) in corners) {
      canvas.drawRect(at & Size.square(unit), Paint()..color = color);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(sample.width, sample.height);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}
