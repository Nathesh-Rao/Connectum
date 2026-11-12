import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/widgets/app_refresh.dart';
import 'package:connectum/core/widgets/app_spinner.dart';

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('AppSpinner', () {
    testWidgets('renders at each preset radius', (tester) async {
      for (final size in AppSpinnerSize.values) {
        await tester.pumpWidget(_host(AppSpinner(size: size)));
        final indicator = tester.widget<CupertinoActivityIndicator>(
          find.byType(CupertinoActivityIndicator),
        );
        expect(indicator.radius, size.extent / 2);
      }
      expect(AppSpinnerSize.values.map((s) => s.extent), [
        16.0,
        20.0,
        24.0,
        32.0,
      ]);
    });

    testWidgets('applies the colour', (tester) async {
      await tester.pumpWidget(
        _host(const AppSpinner(color: AppColors.white)),
      );
      expect(
        tester
            .widget<CupertinoActivityIndicator>(
              find.byType(CupertinoActivityIndicator),
            )
            .color,
        AppColors.white,
      );
    });

    testWidgets('is static when animations are disabled', (tester) async {
      await tester.pumpWidget(
        _host(const AppSpinner(), disableAnimations: true),
      );
      expect(
        tester
            .widget<CupertinoActivityIndicator>(
              find.byType(CupertinoActivityIndicator),
            )
            .animating,
        isFalse,
      );
    });

    testWidgets('keeps the Loading label when standalone', (tester) async {
      await tester.pumpWidget(_host(const AppSpinner(isStandalone: true)));
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });
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
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      done.complete();
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('a short pull does not refresh', (tester) async {
      var calls = 0;
      await tester.pumpWidget(list(() async => calls++));
      await tester.drag(find.text('0'), const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });
  });
}
