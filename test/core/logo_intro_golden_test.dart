import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/widgets/logo_intro/logo_intro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _shot(
  WidgetTester tester,
  String name,
  double t, {
  Color background = AppColors.white,
  Color ink = AppColors.ink,
}) async {
  tester.view.physicalSize = const Size(300, 300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('shot'),
      child: ColoredBox(
        color: background,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: LogoIntro(size: 300, ink: ink, timeOverride: ValueNotifier(t)),
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
  const times = <(String, double)>[
    ('t0_2', 0.2),
    ('t0_7', 0.7),
    ('t1_4', 1.4),
    ('t2_0', 2.0),
    ('t2_8', 2.8),
    ('t3_4', 3.4),
    ('t4_1', 4.1),
    ('t4_6', 4.6),
    ('end', IntroTiming.duration),
  ];
  for (final (name, t) in times) {
    testWidgets('golden $name', (tester) => _shot(tester, name, t));
  }
  testWidgets(
    'golden end on navy with white ink',
    (tester) => _shot(
      tester,
      'end_navy',
      IntroTiming.duration,
      background: AppColors.ink,
      ink: AppColors.white,
    ),
  );
}
