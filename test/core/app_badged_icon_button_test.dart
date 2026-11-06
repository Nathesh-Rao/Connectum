import 'package:connectum/core/widgets/app_badged_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, int count, VoidCallback onTap) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppBadgedIconButton(
                icon: Icons.notifications_none,
                semanticLabel: 'Notifications',
                count: count,
                onPressed: onTap,
              ),
            ),
          ),
        ),
      );

  testWidgets('the hit area is 48 by 48', (tester) async {
    await pump(tester, 5, () {});
    expect(
      tester.getSize(find.byType(AppBadgedIconButton)),
      const Size(48, 48),
    );
  });

  testWidgets('a tap on the badge opens, once', (tester) async {
    var taps = 0;
    await pump(tester, 5, () => taps++);
    await tester.tap(find.text('5'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
  });

  testWidgets('taps on the icon and on the corner of the area open', (
    tester,
  ) async {
    var taps = 0;
    await pump(tester, 0, () => taps++);
    final box = tester.getRect(find.byType(AppBadgedIconButton));
    await tester.tap(find.byIcon(Icons.notifications_none));
    await tester.tapAt(box.bottomLeft + const Offset(1, -1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 2);
  });
}
