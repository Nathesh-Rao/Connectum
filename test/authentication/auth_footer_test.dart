import 'package:connectum/core/theme/app_theme.dart';
import 'package:connectum/core/widgets/app_agile_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, double width, double scale) async {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 640),
          textScaler: TextScaler.linear(scale),
        ),
        child: const Scaffold(body: Column(children: [AppAgileFooter()])),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the line, the logo and the semantics label', (
    tester,
  ) async {
    await _pump(tester, 360, 1);
    expect(find.byKey(const ValueKey('agile-logo')), findsOneWidget);
    expect(find.textContaining('From the', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('Agile Labs Suite', findRichText: true),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('From the Agile Labs Suite'), findsOneWidget);
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('agile-logo')),
    );
    expect(image.color, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits at 320 px and 1.5x text', (tester) async {
    await _pump(tester, 320, 1.5);
    expect(tester.takeException(), isNull);
    final box = tester.getRect(find.byType(AppAgileFooter));
    expect(box.width, lessThanOrEqualTo(320));
    final logo = tester.getRect(find.byKey(const ValueKey('agile-logo')));
    expect(logo.left, greaterThanOrEqualTo(0));
    expect(logo.right, lessThanOrEqualTo(320));
  });
}
