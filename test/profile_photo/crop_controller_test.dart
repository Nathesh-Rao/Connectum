import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:connectum/features/profile_photo/profile_photo_crop_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png(int w, int h) async {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  final image = await r.endRecording().toImage(w, h);
  return (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
}

void main() {
  testWidgets('loads, takes the frame size and follows gestures', (
    tester,
  ) async {
    late ProfilePhotoCropController c;
    await tester.runAsync(() async {
      c = ProfilePhotoCropController(bytes: await _png(400, 200));
      c.onInit();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    expect(c.isLoading.value, isFalse);
    expect(c.crop.value, isNull); // no frame size yet

    c.setBox(200);
    expect(c.crop.value, isNotNull);
    expect(c.canReset, isFalse);

    c.onScaleStart(ScaleStartDetails(localFocalPoint: const Offset(100, 100)));
    expect(c.isMoving.value, isTrue);
    c.onScaleUpdate(
      ScaleUpdateDetails(localFocalPoint: const Offset(130, 100), scale: 2),
    );
    c.onScaleEnd(ScaleEndDetails());
    expect(c.isMoving.value, isFalse);
    expect(c.crop.value!.zoom, closeTo(2, 1e-9));
    expect(c.canReset, isTrue);

    c.rotate(1);
    expect(c.crop.value!.quarterTurns, 1);
    c.setStraighten(10);
    expect(c.straightenDegrees, closeTo(10, 1e-6));
    c.setZoomSlider(1);
    expect(c.crop.value!.zoom, 4);

    c.reset();
    expect(c.canReset, isFalse);
  });

  testWidgets('a file that is not a picture ends in the failed state', (
    tester,
  ) async {
    late ProfilePhotoCropController c;
    await tester.runAsync(() async {
      c = ProfilePhotoCropController(bytes: Uint8List.fromList([1, 2, 3, 4]));
      c.onInit();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    expect(c.hasLoadFailed.value, isTrue);
    expect(c.photo.value, isNull);
    expect(c.isLoading.value, isFalse);
  });
}
