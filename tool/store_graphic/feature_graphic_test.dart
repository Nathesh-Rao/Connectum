import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:connectum/core/widgets/logo_loader/logo_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _width = 1024.0;
const _height = 500.0;
const _titleSize = 96.0;
const _capHeightRatio = 0.7;
const _logoVisualRatio = 0.742;
const _logoToCapRatio = 1.15;

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = await File('assets/fonts/$file').readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

Uint8List _encodeRgbPng(int width, int height, ByteData rgba) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    for (var x = 0; x < width; x++) {
      final o = (y * width + x) * 4;
      raw
        ..addByte(rgba.getUint8(o))
        ..addByte(rgba.getUint8(o + 1))
        ..addByte(rgba.getUint8(o + 2));
    }
  }
  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> body) {
    final head = ByteData(4)..setUint32(0, body.length);
    final typed = [...type.codeUnits, ...body];
    final crc = ByteData(4)..setUint32(0, _crc32(typed));
    out
      ..add(head.buffer.asUint8List())
      ..add(typed)
      ..add(crc.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', ZLibCodec(level: 9).encode(raw.toBytes()));
  chunk('IEND', const []);
  return out.toBytes();
}

void main() {
  final isEnabled = Platform.environment['STORE_GRAPHIC'] == '1';

  testWidgets('writes the Play Store feature graphic', (tester) async {
    tester.view
      ..physicalSize = const Size(_width, _height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(
      () => _loadFont('PlusJakartaSans', const [
        'PlusJakartaSans-Regular.ttf',
        'PlusJakartaSans-Bold.ttf',
      ]),
    );

    final art = await tester.runAsync(() async {
      final bytes = await File('design/store/feature_art.png').readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      return (await codec.getNextFrame()).image;
    });

    const titleStyle = TextStyle(
      fontFamily: 'PlusJakartaSans',
      fontSize: _titleSize,
      fontWeight: FontWeight.w700,
      height: 1,
      letterSpacing: -1,
      color: Color(0xFF2A2523),
    );
    const taglineStyle = TextStyle(
      fontFamily: 'PlusJakartaSans',
      fontSize: 30,
      fontWeight: FontWeight.w400,
      height: 1.2,
      letterSpacing: 0.5,
      color: Color(0xFF6B625D),
    );

    final titleWidth = (TextPainter(
      text: const TextSpan(text: 'Connectum', style: titleStyle),
      textDirection: TextDirection.ltr,
    )..layout()).width;
    expect(
      titleWidth,
      isNot(closeTo(9 * _titleSize, 1)),
      reason: 'Ahem fallback font was rendered',
    );

    const logoSize =
        _titleSize * _capHeightRatio * _logoToCapRatio / _logoVisualRatio;
    final controller = LogoLoaderController();
    addTearDown(controller.dispose);
    final key = GlobalKey();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: _width,
              height: _height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFFF4F2EE)),
                  RawImage(image: art, fit: BoxFit.cover),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LogoLoader(controller: controller, size: logoSize),
                            const SizedBox(width: 12),
                            const Text('Connectum', style: titleStyle),
                          ],
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'Chat, tasks and approvals in one place',
                          style: taglineStyle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      Directory('design/store/out').createSync(recursive: true);
      for (final (ratio, name) in [
        (1.0, 'feature_graphic_1024x500.png'),
        (2.0, 'feature_graphic_2048x1000.png'),
      ]) {
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = (await image.toByteData())!;
        final png = _encodeRgbPng(image.width, image.height, data);
        File('design/store/out/$name').writeAsBytesSync(png);
      }
    });
  }, skip: !isEnabled);
}
