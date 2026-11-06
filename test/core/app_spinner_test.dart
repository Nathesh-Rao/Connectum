import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

import 'package:connectum/core/widgets/app_refresh.dart';
import 'package:connectum/core/widgets/app_spinner.dart';

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: Center(child: child)),
  ),
);

Future<void> _load(WidgetTester tester) async {
  await tester.runAsync(() => AssetLottie(AppSpinner.asset).load());
}

void main() {
  testWidgets('renders at each preset size', (tester) async {
    await _load(tester);
    for (final size in AppSpinnerSize.values) {
      await tester.pumpWidget(_host(AppSpinner(size: size)));
      await tester.pump();
      final box = tester.getSize(
        find.ancestor(of: find.byType(Lottie), matching: find.byType(ClipRect)),
      );
      expect(box, Size(size.extent, size.extent));
      expect(find.byType(Lottie), findsOneWidget);
    }
    expect(AppSpinnerSize.values.map((s) => s.extent), [
      16.0,
      20.0,
      24.0,
      32.0,
    ]);
  });

  group('AppRefresh', () {
    Widget list(Future<void> Function() onRefresh) => _host(
      SizedBox(
        height: 500,
        child: AppRefresh(
          onRefresh: onRefresh,
          slivers: [
            SliverList.builder(
              itemCount: 20,
              itemBuilder: (context, i) =>
                  SizedBox(height: 60, child: Text('$i')),
            ),
          ],
        ),
      ),
    );

    testWidgets('a long pull refreshes once and collapses after', (
      tester,
    ) async {
      await _load(tester);
      var calls = 0;
      final done = Completer<void>();
      await tester.pumpWidget(
        list(() {
          calls++;
          return done.future;
        }),
      );
      await tester.drag(find.text('0'), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, 1);
      expect(find.byType(Lottie), findsOneWidget);
      done.complete();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(Lottie), findsNothing);
    });

    testWidgets('a short pull does not refresh', (tester) async {
      await _load(tester);
      var calls = 0;
      await tester.pumpWidget(list(() async => calls++));
      await tester.drag(find.text('0'), const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });
  });
}
