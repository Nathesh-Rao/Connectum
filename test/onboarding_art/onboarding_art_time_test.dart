import 'dart:ui';

import 'package:connectum/core/widgets/onboarding_art/onboarding_art.dart';
import 'package:connectum/core/widgets/onboarding_art/onboarding_art_speed.dart';
import 'package:connectum/core/widgets/onboarding_art/onboarding_art_palette.dart';
import 'package:connectum/core/widgets/onboarding_art/svg_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(OnboardingArtController c, {OnboardingArtKind kind = OnboardingArtKind.shield}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: SizedBox(
          width: 400,
          height: 300,
          child: OnboardingArt(kind: kind, controller: c),
        ),
      ),
    );

const _frame = Duration(milliseconds: 16);

Future<void> _start(WidgetTester tester, OnboardingArtController c) async {
  await tester.pumpWidget(_host(c));
  await tester.pump(); // the ticker's first frame (elapsed 0)
}

Future<void> _run(WidgetTester tester, Duration d) async {
  var left = d;
  while (left > Duration.zero) {
    final step = left < _frame ? left : _frame;
    await tester.pump(step);
    left -= step;
  }
}

Future<List<int>> _pixels(OnboardingArtKind kind, double t) async {
  final scene = kind.build(OnboardingArtPalette.authored);
  final art = kind.bind(scene);
  const w = 300;
  final h = (w * scene.viewBox.height / scene.viewBox.width).round();
  final rec = PictureRecorder();
  final c = Canvas(rec);
  c.scale(w / scene.viewBox.width);
  c.translate(-scene.viewBox.left, -scene.viewBox.top);
  art.render(t);
  SvgRenderer(scene).paint(c);
  final img = await rec.endRecording().toImage(w, h);
  return (await img.toByteData())!.buffer.asUint8List();
}

void main() {
  testWidgets('at 1x, t is real elapsed seconds: 1.0 s gives 1.0, 5.0 s gives 5.0', (tester) async {
    final c = OnboardingArtController()..speed = 1.0;
    addTearDown(c.dispose);
    await _start(tester, c);
    await _run(tester, const Duration(seconds: 1));
    expect(c.time.value, closeTo(1.0, 0.017));
    await _run(tester, const Duration(seconds: 4));
    expect(c.time.value, closeTo(5.0, 0.017));
  });

  testWidgets('every animation plays at its constant, 1.25 by default: 1.0 s gives 1.25', (tester) async {
    expect([kShieldSpeed, kNetworkSpeed, kBuildingsSpeed], everyElement(1.25));
    for (final kind in OnboardingArtKind.values) {
      final c = OnboardingArtController();
      await tester.pumpWidget(_host(c, kind: kind));
      await tester.pump();
      await _run(tester, const Duration(seconds: 1));
      expect(c.speed, 1.25, reason: kind.name);
      expect(c.time.value, closeTo(1.25, 0.03), reason: kind.name);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });

  testWidgets('a dropped frame skips ahead: one 300 ms pump advances t by 0.375 at 1.25x', (tester) async {
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    await _start(tester, c);
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.time.value, closeTo(0.375, 1e-6));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(c.time.value, closeTo(2.25, 1e-6), reason: 'no cap per frame');
  });

  testWidgets('a dropped frame advances 0.3 at 1x', (tester) async {
    final c = OnboardingArtController()..speed = 1.0;
    addTearDown(c.dispose);
    await _start(tester, c);
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.time.value, closeTo(0.3, 1e-6));
  });

  testWidgets('a controller outside a widget plays at 1x', (tester) async {
    expect(OnboardingArtController().speed, 1.0);
  });

  testWidgets('one network loop takes period / 1.25 real seconds at the default, period / 2 at 2x', (tester) async {
    final period = OnboardingArtKind.network
        .bind(OnboardingArtKind.network.build(OnboardingArtPalette.authored))
        .info['period']! as double;
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    await tester.pumpWidget(_host(c, kind: OnboardingArtKind.network));
    await tester.pump();
    await _run(tester, Duration(milliseconds: (period / 1.25 * 1000).round()));
    expect(c.time.value, closeTo(period, 0.06));
    c.speed = 2.0;
    c.play();
    await tester.pump();
    await _run(tester, Duration(milliseconds: (period / 2 * 1000).round()));
    expect(c.time.value, closeTo(period, 0.06));
  });

  testWidgets('the speed override beats the constant and can be reset', (tester) async {
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    await _start(tester, c);
    expect(c.isDefaultSpeed, isTrue);
    c.speed = 2.0;
    await tester.pump();
    await _run(tester, const Duration(seconds: 1));
    expect(c.time.value, closeTo(2.0, 0.07));
    c.useDefaultSpeed();
    expect(c.speed, 1.25);
  });

  testWidgets('pause and resume do not jump or slow the time', (tester) async {
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    await _start(tester, c);
    await _run(tester, const Duration(milliseconds: 500));
    final atPause = c.time.value;
    c.pause();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(c.time.value, atPause);
    c.resume();
    await tester.pump();
    await _run(tester, const Duration(milliseconds: 500));
    expect(c.time.value, closeTo(atPause + 0.5 * 1.25, 0.04));
  });

  testWidgets('changing the speed while running re-bases and keeps real time', (tester) async {
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    await _start(tester, c);
    await _run(tester, const Duration(seconds: 1));
    final before = c.time.value;
    c.speed = 0.5;
    await tester.pump();
    await _run(tester, const Duration(seconds: 1));
    expect(c.time.value, closeTo(before + 0.5, 0.04));
  });

  testWidgets('replay restarts at 0 and runs at the art speed', (tester) async {
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    await _start(tester, c);
    await _run(tester, const Duration(seconds: 2));
    c.play();
    expect(c.time.value, 0);
    await tester.pump();
    await _run(tester, const Duration(seconds: 1));
    expect(c.time.value, closeTo(1.25, 0.05));
  });

  testWidgets('time keeps counting past the loop point without restarting the intro', (tester) async {
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    await _start(tester, c);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 4));
    expect(c.time.value, closeTo(7.0 * 1.25, 1e-6));
  });

  group('loop structure', () {
    test('shield: intro 1.95 s then 3.9 s cycles, message variant = cycle mod 3', () {
      final scene = OnboardingArtKind.shield.build(OnboardingArtPalette.authored);
      final art = OnboardingArtKind.shield.bind(scene);
      final variants = [scene.byId('msgA'), scene.byId('msgB'), scene.byId('msgC')];
      final seen = <int>[];
      for (var k = 0; k < 7; k++) {
        art.render(1.95 + k * 3.9 + 0.3);
        seen.add(variants.indexWhere((v) => v.display));
      }
      expect(seen, [0, 1, 2, 0, 1, 2, 0]);
      art.render(1.9);
      expect(scene.byId('msg').visible, isFalse, reason: 'no tile during the intro');
      art.render(1.95 + 0.3);
      expect(scene.byId('msg').visible, isTrue);
    });

    test('network wraps at its (trimmed) period', () async {
      final period = OnboardingArtKind.network
          .bind(OnboardingArtKind.network.build(OnboardingArtPalette.authored))
          .info['period']! as double;
      final a = await _pixels(OnboardingArtKind.network, 7.3);
      final b = await _pixels(OnboardingArtKind.network, 7.3 + period);
      final c = await _pixels(OnboardingArtKind.network, 7.3 + 3 * period);
      expect(b, a);
      expect(c, a);
    });

    test('the loop in real seconds is the script period divided by the speed', () {
      final net = OnboardingArtKind.network
          .bind(OnboardingArtKind.network.build(OnboardingArtPalette.authored));
      final bld = OnboardingArtKind.buildings
          .bind(OnboardingArtKind.buildings.build(OnboardingArtPalette.authored));
      final p = net.info['period']! as double;
      expect(loopSeconds(p, kNetworkSpeed), closeTo(p / 1.25, 1e-9));
      expect(loopSeconds(3.9, kShieldSpeed), closeTo(3.12, 1e-9));
      expect(loopSeconds(bld.info['period']! as double, kBuildingsSpeed),
          closeTo((bld.info['period']! as double) / 1.25, 1e-9));
      // a different constant gives a different loop length
      expect(loopSeconds(p, 1.0), isNot(closeTo(loopSeconds(p, 1.25), 0.1)));
      expect(loopSeconds(p, 2.0), closeTo(p / 2, 1e-9));
    });

    test('buildings repeats every period after the intro', () async {
      final art = OnboardingArtKind.buildings.bind(
        OnboardingArtKind.buildings.build(OnboardingArtPalette.authored),
      );
      final loop0 = art.info['loopStart']! as double;
      final period = art.info['period']! as double;
      final t = loop0 + 2.2;
      expect(await _pixels(OnboardingArtKind.buildings, t + period), await _pixels(OnboardingArtKind.buildings, t));
      expect(await _pixels(OnboardingArtKind.buildings, t + 2 * period), await _pixels(OnboardingArtKind.buildings, t));
    });
  });
}
