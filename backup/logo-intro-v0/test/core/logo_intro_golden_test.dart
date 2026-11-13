import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/widgets/logo_intro/logo_intro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _shot(
  WidgetTester tester,
  String name,
  double t, {
  Color background = AppColors.white,
  Color textColor = AppColors.ink,
}) async {
  tester.view.physicalSize = const Size(300, 310);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('shot'),
      child: ColoredBox(
        color: background,
        child: Center(
          child: LogoIntroFrame(
            time: ValueNotifier<double>(t),
            width: 240,
            textColor: textColor,
          ),
        ),
      ),
    ),
  );
  await expectLater(
    find.byKey(const Key('shot')),
    matchesGoldenFile('goldens/logo_intro_$name.png'),
  );
}

void main() {
  for (final t in [150, 400, 800, 1100, 1400, 1800, 2400, 2700, 3300]) {
    testWidgets('logo intro at $t ms', (tester) async {
      await _shot(tester, 't$t', t.toDouble());
    });
  }

  testWidgets('logo intro final frame on navy with white text', (tester) async {
    await _shot(
      tester,
      'navy_final',
      3300,
      background: AppColors.ink,
      textColor: AppColors.white,
    );
  });
}
