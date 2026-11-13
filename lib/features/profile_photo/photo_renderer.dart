import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../core/theme/app_colors.dart';
import 'crop_math.dart';

/// A decoded picture and the size of the original it came from. The screen
/// shows a downscaled copy; the cut-out is always taken from the original.
class DecodedPhoto {
  const DecodedPhoto(this.image, this.sourceW, this.sourceH);

  final ui.Image image;
  final int sourceW;
  final int sourceH;
}

class PhotoRenderer {
  PhotoRenderer._();

  /// The saved picture: 512 x 512, like the web's cropper.
  static const outputSize = 512;

  /// The longest side of the copy shown on screen.
  static const previewSide = 1600;

  /// The longest side the original is decoded at for the cut-out. A photo
  /// larger than this is read smaller; 512 output pixels need far less.
  static const sourceSide = 4096;

  /// Decodes [bytes] no larger than [maxSide] on the long edge. Throws when
  /// the bytes are not a picture the engine can read.
  static Future<DecodedPhoto> decode(Uint8List bytes, int maxSide) async {
    // The codec call takes over the buffer and disposes it itself.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    var sourceW = 0, sourceH = 0;
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        sourceW = w;
        sourceH = h;
        final longest = w > h ? w : h;
        if (longest <= maxSide) return ui.TargetImageSize();
        final ratio = maxSide / longest;
        return ui.TargetImageSize(
          width: (w * ratio).round().clamp(1, maxSide),
          height: (h * ratio).round().clamp(1, maxSide),
        );
      },
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return DecodedPhoto(frame.image, sourceW, sourceH);
  }

  /// Draws [photo] under the frame the way [state] says, into a [size] square
  /// on a white ground (a see-through picture has no see-through avatar), and
  /// encodes it as PNG.
  ///
  /// The output is drawn fresh from pixels, so nothing of the original file
  /// travels with it: no EXIF, no GPS position, no camera name, no
  /// thumbnail. The server only accepts PNG, JPEG, GIF or WebP and Flutter
  /// can encode only PNG without a package, so the upload is a PNG.
  static Future<Uint8List> render(
    ui.Image photo,
    CropState state, {
    int size = outputSize,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = AppColors.white,
    );
    paint(canvas, photo, state, size.toDouble());
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('The picture could not be encoded.');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  /// Paints [photo] for [state] into a square of [side] pixels (the frame).
  /// The one drawing used by the screen and by [render], so what is shown is
  /// what is saved.
  static void paint(
    Canvas canvas,
    ui.Image photo,
    CropState state,
    double side,
  ) {
    // The state counts source pixels; [photo] may be a smaller copy.
    final ratio = state.imageW / photo.width;
    canvas.save();
    canvas.scale(side / state.box);
    canvas.translate(
      state.box / 2 + state.center.dx,
      state.box / 2 + state.center.dy,
    );
    canvas.rotate(state.angle);
    canvas.scale(state.scale * ratio);
    canvas.translate(-photo.width / 2, -photo.height / 2);
    canvas.drawImage(
      photo,
      Offset.zero,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true,
    );
    canvas.restore();
  }
}
