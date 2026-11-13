import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/widgets/logo_intro/logo_intro.dart';
import 'package:connectum/core/widgets/logo_intro/logo_intro_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 240.0;
final _h = (_w * logoIntroHeight / logoIntroWidth).ceil().toDouble();

Future<Uint8List> _pixels(
  WidgetTester tester,
  void Function(Canvas canvas, Size size) draw,
) async {
  final size = Size(_w, _h);
  final bytes = await tester.runAsync(() async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.white);
    draw(canvas, size);
    final image = await rec.endRecording().toImage(_w.toInt(), _h.toInt());
    return (await image.toByteData())!.buffer.asUint8List();
  });
  return bytes!;
}

Future<Uint8List> _frame(
  WidgetTester tester,
  double t, {
  Color textColor = AppColors.ink,
}) {
  final time = ValueNotifier<double>(t);
  return _pixels(
    tester,
    (c, s) => LogoIntroPainter(time: time, textColor: textColor).paint(c, s),
  );
}

bool _isWhite(Uint8List p, int i) =>
    p[i] == 255 && p[i + 1] == 255 && p[i + 2] == 255;

void main() {
  group('generator', () {
    final svg = 'design/brand/connectum_logo_animated.svg';
    final out = 'lib/core/widgets/logo_intro/logo_intro_data.dart';

    test('is deterministic and the committed file is up to date', () {
      final dir = Directory.systemTemp.createTempSync('logo_intro_gen');
      addTearDown(() => dir.deleteSync(recursive: true));
      final a = '${dir.path}/a.dart', b = '${dir.path}/b.dart';
      for (final f in [a, b]) {
        final r = Process.runSync('python3', [
          'tool/logo/generate_logo_intro_data.py',
          svg,
          f,
        ]);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      }
      expect(File(a).readAsStringSync(), File(b).readAsStringSync());
      expect(File(a).readAsStringSync(), File(out).readAsStringSync());
    });

    test('expected big and top parts', () {
      final big = <int>{}, top = <int>{};
      for (var i = 0; i < logoIntroParts.length; i++) {
        if (logoIntroParts[i].isBig) big.add(i);
        if (logoIntroParts[i].isTop) top.add(i);
      }
      expect(logoIntroParts, hasLength(57));
      expect(big, {32});
      expect(top, {2, 7, 8, 9});
    });
  });

  group('timeline', () {
    final tl = LogoIntroTimeline();

    test('final frame: identity transform, opacity 1, bounds = data', () {
      final pose = LogoIntroPose();
      final paths = LogoIntroPaths.instance;
      for (var i = 0; i < logoIntroParts.length; i++) {
        tl.poseAt(i, kLogoIntroTotalMs, pose);
        expect(pose.isVisible, isTrue);
        expect(pose.isIdentity, isTrue, reason: 'part $i');
        expect(pose.along, 1);
        expect(pose.perp, 1);
        expect(pose.angle, 0);
        expect(pose.opacity, 1);
        expect(pose.x, closeTo(logoIntroParts[i].focusX, 1e-9));
        final b = paths.parts[i].getBounds();
        final p = logoIntroParts[i];
        expect(b.left, closeTo(p.left, 0.01));
        expect(b.top, closeTo(p.top, 0.01));
        expect(b.right, closeTo(p.right, 0.01));
        expect(b.bottom, closeTo(p.bottom, 0.01));
      }
      tl.textAt(kLogoIntroTotalMs, pose);
      expect(pose.isIdentity, isTrue);
      expect(pose.opacity, 1);
      expect(pose.y, logoIntroTextCenterY);
      final tb = paths.text.getBounds();
      expect(tb.left, closeTo(logoIntroTextLeft, 0.01));
      expect(tb.bottom, closeTo(logoIntroTextBottom, 0.01));
    });

    test('a part never starts before one with a smaller s', () {
      for (var a = 0; a < logoIntroParts.length; a++) {
        for (var b = 0; b < logoIntroParts.length; b++) {
          // The index tie-break may reorder parts closer than 57 * 0.0004.
          final sa = logoIntroParts[a].s - a * 0.0004;
          final sb = logoIntroParts[b].s - b * 0.0004;
          if (sa > sb + 57 * 0.0004) {
            expect(tl.starts[a], greaterThanOrEqualTo(tl.starts[b]));
          }
        }
      }
    });

    test('all parts are done before the wordmark starts', () {
      final last = tl.starts.reduce(math.max) + kLogoIntroPartDur;
      expect(last, lessThanOrEqualTo(kLogoIntroTextA + 20));
    });
  });

  group('frames', () {
    testWidgets(
      't = 0 draws no part and no wordmark, only a head of radius 0',
      (tester) async {
        final tl = LogoIntroTimeline();
        final pose = LogoIntroPose();
        for (var i = 0; i < logoIntroParts.length; i++) {
          tl.poseAt(i, 0, pose);
          expect(pose.isVisible, isFalse);
        }
        tl.textAt(0, pose);
        expect(pose.isVisible, isFalse);
        final head = LogoIntroHead();
        tl.headAt(0, head);
        expect(head.radius, 0);
        final px = await _frame(tester, 0);
        for (var i = 0; i < px.length; i += 4) {
          expect(_isWhite(px, i), isTrue);
        }
      },
    );

    testWidgets('shortly after 0 only the head circle is visible', (
      tester,
    ) async {
      final px = await _frame(tester, 60);
      final head = LogoIntroHead();
      LogoIntroTimeline().headAt(60, head);
      final k = _w / logoIntroWidth;
      var count = 0;
      for (var i = 0; i < px.length; i += 4) {
        if (_isWhite(px, i)) continue;
        count++;
        final x = (i ~/ 4) % _w.toInt() + 0.5, y = (i ~/ 4) ~/ _w.toInt() + 0.5;
        expect(
          math.sqrt(math.pow(x - head.x * k, 2) + math.pow(y - head.y * k, 2)),
          lessThanOrEqualTo(head.radius * k + 1.5),
        );
      }
      expect(count, greaterThan(0));
    });

    testWidgets('final frame equals the plain artwork', (tester) async {
      final actual = await _frame(tester, kLogoIntroTotalMs);
      final paths = LogoIntroPaths.instance;
      final expected = await _pixels(tester, (c, s) {
        c.scale(s.width / logoIntroWidth);
        c.drawPath(paths.text, Paint()..color = AppColors.ink);
        for (var i = 0; i < logoIntroParts.length; i++) {
          c.drawPath(
            paths.parts[i],
            Paint()..color = Color(logoIntroParts[i].fill),
          );
        }
      });
      expect(actual, expected);
    });

    testWidgets('the wordmark is painted behind the C parts', (tester) async {
      const t = 2260.0;
      final tl = LogoIntroTimeline();
      final paths = LogoIntroPaths.instance;
      final withText = await _frame(
        tester,
        t,
        textColor: const Color(0xFFFF0000),
      );
      final noText = await _frame(
        tester,
        t,
        textColor: const Color(0x00000000),
      );
      // Where a part is painted the wordmark must not show through.
      var overlap = 0;
      final pose = LogoIntroPose();
      tl.textAt(t, pose);
      final m = Matrix4.identity()
        ..translateByDouble(pose.x, pose.y, 0, 1)
        ..scaleByDouble(pose.along, pose.perp, 1, 1)
        ..translateByDouble(-logoIntroTextCenterX, -logoIntroTextCenterY, 0, 1);
      final text = paths.text.transform(m.storage);
      final k = _w / logoIntroWidth;
      for (var py = 0; py < _h; py++) {
        for (var px = 0; px < _w; px++) {
          final i = (py * _w.toInt() + px) * 4;
          // Interior pixels only: an edge pixel blends the part with what is behind.
          final w = _w.toInt();
          if (px < 1 || py < 1 || px >= w - 1 || py >= _h - 1) continue;
          if ([-4, 4, -4 * w, 4 * w, 0].any((o) => _isWhite(noText, i + o))) {
            continue;
          }
          // Anti-aliased part edges blend with what is behind them: allow a little.
          for (var c = 0; c < 3; c++) {
            expect(
              (withText[i + c] - noText[i + c]).abs(),
              lessThanOrEqualTo(20),
              reason: 'pixel $px,$py shows the wordmark over a part',
            );
          }
          if (text.contains(Offset((px + 0.5) / k, (py + 0.5) / k))) overlap++;
        }
      }
      expect(overlap, greaterThan(20), reason: 'the test must hit an overlap');
      var changed = 0;
      for (var i = 0; i < withText.length; i += 4) {
        if (withText[i + 1] != noText[i + 1]) changed++;
      }
      expect(changed, greaterThan(50), reason: 'the wordmark is visible');
    });

    testWidgets('reduced motion shows the final frame and completes at once', (
      tester,
    ) async {
      var completed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: LogoIntro(onCompleted: () => completed++),
          ),
        ),
      );
      await tester.pump();
      expect(completed, 1);
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(LogoIntro),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(
        (paint.painter! as LogoIntroPainter).time.value,
        kLogoIntroTotalMs,
      );
    });

    testWidgets('plays once, completes after 3300 ms and holds', (
      tester,
    ) async {
      var completed = 0;
      await tester.pumpWidget(
        MaterialApp(home: LogoIntro(onCompleted: () => completed++)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3200));
      expect(completed, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(completed, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(completed, 1);
    });
  });
}
