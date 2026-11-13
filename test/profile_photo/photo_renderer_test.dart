import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:connectum/features/profile_photo/crop_math.dart';
import 'package:connectum/features/profile_photo/photo_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

/// A picture of [w] x [h] pixels: left half red, right half blue.
Future<ui.Image> _halves(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w / 2, h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(w / 2, 0, w / 2, h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF0000FF),
  );
  final image = await recorder.endRecording().toImage(w, h);
  return image;
}

Future<Uint8List> _pngOf(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<Uint8List> _rgba(Uint8List png) async {
  final decoded = await PhotoRenderer.decode(png, 4096);
  final data = await decoded.image.toByteData();
  return data!.buffer.asUint8List();
}

ui.Color _at(Uint8List rgba, int size, int x, int y) {
  final i = (y * size + x) * 4;
  return ui.Color.fromARGB(rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2]);
}

void main() {
  testWidgets('output is a 512 x 512 PNG', (tester) async {
    await tester.runAsync(() async {
      final photo = await _halves(800, 400);
      final state = CropState(imageW: 800, imageH: 400, box: 300);
      final png = await PhotoRenderer.render(photo, state);
      expect(png.sublist(0, 8), [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]);
      final back = await PhotoRenderer.decode(png, 4096);
      expect(back.image.width, PhotoRenderer.outputSize);
      expect(back.image.height, PhotoRenderer.outputSize);
      expect(png.length, lessThan(8 * 1024 * 1024));
    });
  });

  testWidgets('carries no EXIF, GPS or text chunk from anything', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final photo = await _halves(640, 480);
      final png = await PhotoRenderer.render(
        photo,
        CropState(imageW: 640, imageH: 480, box: 300),
      );
      final text = latin1.decode(png);
      for (final marker in ['eXIf', 'Exif', 'GPS', 'tEXt', 'iTXt', 'zTXt']) {
        expect(text.contains(marker), isFalse, reason: marker);
      }
    });
  });

  testWidgets('the cut-out is the part under the frame', (tester) async {
    await tester.runAsync(() async {
      // 800 x 400, frame covers the middle 400 x 400: left half of the output
      // is red, right half blue
      final photo = await _halves(800, 400);
      final png = await PhotoRenderer.render(
        photo,
        CropState(imageW: 800, imageH: 400, box: 200),
        size: 64,
      );
      final px = await _rgba(png);
      expect(_at(px, 64, 8, 32).r, greaterThan(0.9));
      expect(_at(px, 64, 8, 32).b, lessThan(0.1));
      expect(_at(px, 64, 56, 32).b, greaterThan(0.9));
    });
  });

  testWidgets('dragged to the left end it is all red', (tester) async {
    await tester.runAsync(() async {
      final photo = await _halves(800, 400);
      final state = CropState(
        imageW: 800,
        imageH: 400,
        box: 200,
      ).panned(const Offset(9999, 0));
      final px = await _rgba(
        await PhotoRenderer.render(photo, state, size: 64),
      );
      expect(_at(px, 64, 4, 32).r, greaterThan(0.9));
      expect(_at(px, 64, 60, 32).r, greaterThan(0.9));
    });
  });

  testWidgets('a quarter turn right moves red from the left to the top', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final photo = await _halves(400, 400);
      final state = CropState(imageW: 400, imageH: 400, box: 200).rotated(1);
      final px = await _rgba(
        await PhotoRenderer.render(photo, state, size: 64),
      );
      // clockwise: the left half goes to the top
      expect(_at(px, 64, 32, 6).r, greaterThan(0.9));
      expect(_at(px, 64, 32, 58).b, greaterThan(0.9));
    });
  });

  testWidgets('a smaller preview copy gives the same cut-out', (tester) async {
    await tester.runAsync(() async {
      final full = await _halves(800, 400);
      final preview = await _halves(400, 200);
      final state = CropState(
        imageW: 800,
        imageH: 400,
        box: 200,
      ).zoomedAround(2);
      final a = await _rgba(await PhotoRenderer.render(full, state, size: 64));
      final b = await _rgba(
        await PhotoRenderer.render(preview, state, size: 64),
      );
      expect(_at(a, 64, 10, 32), _at(b, 64, 10, 32));
      expect(_at(a, 64, 54, 32), _at(b, 64, 54, 32));
    });
  });

  testWidgets('decode keeps the original size and shrinks the copy', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final big = await _pngOf(await _halves(3000, 1500));
      final d = await PhotoRenderer.decode(big, 1000);
      expect(d.sourceW, 3000);
      expect(d.sourceH, 1500);
      expect(d.image.width, 1000);
      expect(d.image.height, 500);
    });
  });
}
