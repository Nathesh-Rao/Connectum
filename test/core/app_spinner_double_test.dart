import 'dart:async';
import 'dart:io';

import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/widgets/app_refresh.dart';
import 'package:connectum/core/widgets/app_spinner/app_spinner_double.dart';
import 'package:connectum/core/widgets/app_spinner/generated/spinner_double_data.dart';
import 'package:connectum/core/widgets/app_spinner/pull_refresh_config.dart';
import 'package:connectum/core/widgets/onboarding_art/svg_path_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ms = Duration(milliseconds: 50);

Future<void> _pumpFor(WidgetTester tester, int ms) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(_ms);
  }
}

Widget _host(Widget child, {bool isReduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: isReduced),
    child: Scaffold(backgroundColor: Colors.white, body: child),
  ),
);

Widget _list(Future<void> Function() onRefresh, {int count = 20}) => _host(
  SizedBox(
    height: 500,
    child: AppRefresh(
      onRefresh: onRefresh,
      slivers: [
        SliverList.builder(
          itemCount: count,
          itemBuilder: (context, i) => SizedBox(height: 60, child: Text('$i')),
        ),
      ],
    ),
  ),
);

Widget _painted(double t, {double progress = 1, bool isFree = true}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Colors.white,
        child: Center(
          child: SizedBox.square(
            dimension: 160,
            child: CustomPaint(
              painter: SpinnerDoublePainter(
                seconds: ValueNotifier(t),
                isFree: isFree,
                progress: progress,
                color: kPullRefreshColor,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  group('generated data', () {
    test('both paths parse and stay inside the viewBox', () {
      expect(spinnerDoublePaths, hasLength(2));
      for (final p in spinnerDoublePaths) {
        final b = parseSvgPath(p.d).bounds;
        expect(b.left, greaterThanOrEqualTo(0));
        expect(b.top, greaterThanOrEqualTo(0));
        expect(b.right, lessThanOrEqualTo(spinnerDoubleViewBoxWidth));
        expect(b.bottom, lessThanOrEqualTo(spinnerDoubleViewBoxHeight));
      }
    });

    test('speeds, directions and pivot match the SVG', () {
      final svg = File(
        'assets/icons/loader/spinner-double.svg',
      ).readAsStringSync();
      final durs = RegExp(
        r'dur="([0-9.]+)s"',
      ).allMatches(svg).map((m) => double.parse(m[1]!)).toList();
      final tos = RegExp(r'to="(-?\d+) (\d+) (\d+)"').allMatches(svg).toList();
      expect(durs, [0.8, 0.6]);
      expect(spinnerDoublePaths.map((p) => p.durationSeconds), durs);
      expect(spinnerDoublePaths.map((p) => p.direction), [1, -1]);
      expect(tos.map((m) => int.parse(m[1]!).sign), [1, -1]);
      for (final p in spinnerDoublePaths) {
        expect([p.pivotX, p.pivotY], [40, 40]);
      }
      expect(spinnerDoubleViewBoxWidth, 80);
      expect(spinnerDoubleViewBoxHeight, 80);
    });

    test('generator output is identical on re-run', () {
      const generated =
          'lib/core/widgets/app_spinner/generated/spinner_double_data.dart';
      final before = File(generated).readAsStringSync();
      final result = Process.runSync('python3', [
        'tool/loader/extract_spinner.py',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File(generated).readAsStringSync(), before);
    });
  });

  group('painter', () {
    test('angles follow speed and direction', () {
      const a = 2 * 3.141592653589793;
      final p1 = spinnerDoublePaths[0];
      final p2 = spinnerDoublePaths[1];
      double at(p, double t) =>
          SpinnerDoublePainter.angleOf(p, isFree: true, t: t, progress: 0);
      expect(at(p1, 0.8), closeTo(a, 1e-9));
      expect(at(p2, 0.6), closeTo(-a, 1e-9));
      expect(at(p1, 0.4), closeTo(a / 2, 1e-9));
      expect(
        SpinnerDoublePainter.angleOf(p1, isFree: false, t: 9, progress: 0.5),
        closeTo(a / 2, 1e-9),
      );
    });

    testWidgets('paints deterministically at several times and progress', (
      tester,
    ) async {
      for (final t in [0.0, 0.1, 0.37, 1.2]) {
        for (final progress in [0.1, 0.5, 1.0]) {
          await tester.pumpWidget(_painted(t, progress: progress));
          expect(tester.takeException(), isNull);
        }
      }
    });
  });

  group('goldens', () {
    for (final t in [0.0, 0.1, 0.2, 0.3]) {
      testWidgets('spinner at t=$t', (tester) async {
        await tester.binding.setSurfaceSize(const Size(200, 200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_painted(t));
        await expectLater(
          find.byType(ColoredBox).first,
          matchesGoldenFile(
            'goldens/spinner/spinner_t${(t * 1000).round()}.png',
          ),
        );
      });
    }
    for (final p in [0.3, 0.6, 1.0]) {
      testWidgets('spinner at progress $p', (tester) async {
        await tester.binding.setSurfaceSize(const Size(200, 200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_painted(0, progress: p, isFree: false));
        await expectLater(
          find.byType(ColoredBox).first,
          matchesGoldenFile(
            'goldens/spinner/spinner_p${(p * 100).round()}.png',
          ),
        );
      });
    }
  });

  group('pull to refresh', () {
    testWidgets('a long pull refreshes once, shows the spinner, hides after', (
      tester,
    ) async {
      var calls = 0;
      final done = Completer<void>();
      await tester.pumpWidget(
        _list(() {
          calls++;
          return done.future;
        }),
      );
      await tester.drag(find.text('0'), const Offset(0, 300));
      await _pumpFor(tester, 500);
      expect(calls, 1);
      expect(find.byType(AppSpinnerDouble), findsOneWidget);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      done.complete();
      await _pumpFor(tester, 2000);
      expect(calls, 1);
      expect(find.byType(AppSpinnerDouble), findsNothing);
    });

    testWidgets('a short pull does nothing', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_list(() async => calls++));
      await tester.drag(find.text('0'), const Offset(0, 30));
      await _pumpFor(tester, 1000);
      expect(calls, 0);
      expect(find.byType(AppSpinnerDouble), findsNothing);
    });

    testWidgets('a failing refresh still hides the spinner', (tester) async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        await tester.pumpWidget(
          _list(() async {
            await Future<void>.delayed(const Duration(seconds: 1));
            throw StateError('boom');
          }),
        );
        await tester.drag(find.text('0'), const Offset(0, 300));
        await _pumpFor(tester, 1500);
        await _pumpFor(tester, 2000);
      }, (e, s) => errors.add(e));
      expect(errors, isNotEmpty);
      expect(find.byType(AppSpinnerDouble), findsNothing);
    });

    testWidgets('an empty list is refreshable', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_list(() async => calls++, count: 0));
      await tester.dragFrom(const Offset(200, 200), const Offset(0, 300));
      await _pumpFor(tester, 500);
      expect(calls, 1);
      await _pumpFor(tester, 2000);
    });

    testWidgets('reduced motion shows the static spinner without a ticker', (
      tester,
    ) async {
      final done = Completer<void>();
      await tester.pumpWidget(
        _host(
          SizedBox(
            height: 500,
            child: AppRefresh(
              onRefresh: () => done.future,
              slivers: [
                SliverList.builder(
                  itemCount: 20,
                  itemBuilder: (context, i) =>
                      SizedBox(height: 60, child: Text('$i')),
                ),
              ],
            ),
          ),
          isReduced: true,
        ),
      );
      await tester.drag(find.text('0'), const Offset(0, 300));
      await _pumpFor(tester, 500);
      expect(find.byType(AppSpinnerDouble), findsOneWidget);
      final painter = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(AppSpinnerDouble),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((w) => w.painter)
          .whereType<SpinnerDoublePainter>()
          .single;
      expect(painter.isFree, isFalse);
      done.complete();
      await _pumpFor(tester, 2000);
    });

    testWidgets('the ticker stops when the route is covered', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  const AppSpinnerDouble(),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(body: Text('top')),
                      ),
                    ),
                    child: const Text('go'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await _pumpFor(tester, 100);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.tap(find.text('go'));
      await _pumpFor(tester, 600);
      expect(find.text('top'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('default colour is the config constant', (tester) async {
      expect(kPullRefreshColor, AppColors.primaryBright);
      await tester.pumpWidget(_host(const AppSpinnerDouble()));
      expect(
        tester.widget<AppSpinnerDouble>(find.byType(AppSpinnerDouble)).color,
        kPullRefreshColor,
      );
    });
  });
}
