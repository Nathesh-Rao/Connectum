import 'dart:io';
import 'dart:math' as math;

import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_spacing.dart';
import 'package:connectum/core/theme/app_theme.dart';
import 'package:connectum/core/widgets/app_button.dart';
import 'package:connectum/core/widgets/app_fab.dart';
import 'package:connectum/core/widgets/app_bubble_surface.dart';
import 'package:connectum/features/debug_palette/button_samples.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

Future<void> _loadFonts() async {
  for (final (family, weights) in [
    ('PlusJakartaSans', ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']),
    ('SpaceGrotesk', ['SemiBold', 'Bold']),
  ]) {
    final loader = FontLoader(family);
    for (final w in weights) {
      final bytes = File('assets/fonts/$family-$w.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

double _ratio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  final h = AppSpacing.controlHeight;
  final cases = <String, (Size, bool)>{
    'button wide 363': (Size(363, h), false),
    'button wide 280': (Size(280, h), false),
    'button medium 220': (Size(220, h), false),
    'button medium 160': (Size(160, h), false),
    'button narrow 159': (Size(159, h), false),
    'button narrow 120': (Size(120, h), false),
    'compact button 200': (Size(200, AppSpacing.compactButtonHeight), false),
    'fab circle': (Size(AppSpacing.fab, AppSpacing.fab), true),
    'fab extended 130': (Size(130, AppSpacing.fab), true),
  };

  test('disc counts per width and FAB shape', () {
    expect(bubbleDiscsFor(Size(363, h)).length, 7);
    expect(bubbleDiscsFor(Size(280, h)).length, 7);
    expect(bubbleDiscsFor(Size(279, h)).length, 5);
    expect(bubbleDiscsFor(Size(160, h)).length, 5);
    expect(bubbleDiscsFor(Size(159, h)).length, 3);
    expect(bubbleDiscsFor(Size(56, 56), isFab: true).length, 3);
    expect(bubbleDiscsFor(Size(130, 56), isFab: true).length, 3);
  });

  test('white on the lightest possible disc stack is at least 4.5:1', () {
    expect(_ratio(AppColors.white, kBubbleBase), greaterThanOrEqualTo(4.5));
    var worst = 99.0;
    cases.forEach((name, c) {
      final stack = bubbleLightestStack(c.$1, isFab: c.$2);
      final ratio = _ratio(AppColors.white, stack);
      worst = math.min(worst, ratio);
      // ignore: avoid_print
      print('$name: $stack -> white ${ratio.toStringAsFixed(2)}:1');
      expect(ratio, greaterThanOrEqualTo(4.5), reason: name);
    });
    // ignore: avoid_print
    print('worst case: white ${worst.toStringAsFixed(2)}:1');
  });

  test('the pressed overlay keeps white at least 4.5:1', () {
    cases.forEach((name, c) {
      final pressed = Color.alphaBlend(
        kBubblePressedColor.withValues(alpha: kBubblePressedOpacity),
        bubbleLightestStack(c.$1, isFab: c.$2),
      );
      expect(_ratio(AppColors.white, pressed), greaterThanOrEqualTo(4.5));
    });
  });

  test('only the label band is calm: at most one disc centred in it', () {
    for (final set in [kBubblesWide, kBubblesMedium, kBubblesNarrow]) {
      final centred = set.where(
        (d) => d.dx > 0.3 && d.dx < 0.7 && d.diameter > 0.5,
      );
      expect(centred, isEmpty);
    }
  });

  group('button goldens', () {
    setUpAll(_loadFonts);

    Future<void> shootWidget(
      WidgetTester tester,
      String name,
      Widget child, {
      Future<void> Function(WidgetTester)? before,
    }) async {
      tester.view.physicalSize = const Size(1200, 240);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('shot'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Padding(padding: const EdgeInsets.all(16), child: child),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await before?.call(tester);
      await expectLater(
        find.byKey(const Key('shot')),
        matchesGoldenFile('goldens/buttons_$name.png'),
      );
    }

    Widget sized(double width, Widget child) =>
        SizedBox(width: width, child: child);

    testWidgets('default wide 363', (t) async {
      await shootWidget(
        t,
        'wide_363',
        sized(
          363,
          AppButton.primary(
            label: 'Continue',
            icon: Icons.arrow_forward,
            onPressed: () {},
          ),
        ),
      );
    });

    testWidgets('medium 220', (t) async {
      await shootWidget(
        t,
        'medium_220',
        sized(220, AppButton.primary(label: 'Continue', onPressed: () {})),
      );
    });

    testWidgets('narrow 140', (t) async {
      await shootWidget(
        t,
        'narrow_140',
        sized(
          140,
          AppButton.primary(
            label: 'Get started',
            isCentered: true,
            onPressed: () {},
          ),
        ),
      );
    });

    testWidgets('disabled', (t) async {
      await shootWidget(
        t,
        'disabled',
        sized(363, const AppButton.primary(label: 'Continue', onPressed: null)),
      );
    });

    testWidgets('loading', (t) async {
      await shootWidget(
        t,
        'loading',
        sized(
          363,
          AppButton.primary(
            label: 'Continue',
            isLoading: true,
            onPressed: () {},
          ),
        ),
      );
    });

    testWidgets('fab circle and extended', (t) async {
      await shootWidget(
        t,
        'fabs',
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFab(
              semanticLabel: 'Add',
              onPressed: () {},
              child: const Icon(Icons.add, color: AppColors.white),
            ),
            const SizedBox(width: 16),
            AppFab(
              semanticLabel: 'New chat',
              label: 'New chat',
              onPressed: () {},
              child: const Icon(Icons.add, color: AppColors.white),
            ),
          ],
        ),
      );
    });

    testWidgets('pressed button', (t) async {
      await shootWidget(
        t,
        'pressed',
        sized(
          363,
          AppButton.primary(
            key: const Key('sample-primary'),
            label: 'Continue',
            icon: Icons.arrow_forward,
            onPressed: () {},
          ),
        ),
        before: (t) async {
          await t.startGesture(
            t.getCenter(find.byKey(const Key('sample-primary'))),
          );
          await t.pump(const Duration(milliseconds: 300));
        },
      );
    });

    testWidgets('pressed fab', (t) async {
      await shootWidget(
        t,
        'pressed_fab',
        AppFab(
          key: const Key('sample-fab'),
          semanticLabel: 'Add',
          onPressed: () {},
          child: const Icon(Icons.add, color: AppColors.white),
        ),
        before: (t) async {
          await t.startGesture(
            t.getCenter(find.byKey(const Key('sample-fab'))),
          );
          await t.pump(const Duration(milliseconds: 300));
        },
      );
    });

    testWidgets('debug samples page', (t) async {
      t.view.physicalSize = const Size(840, 1500);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        RepaintBoundary(
          key: const Key('shot'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: ButtonSamples(),
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byKey(const Key('shot')),
        matchesGoldenFile('goldens/buttons_default.png'),
      );
    });
  });
}
