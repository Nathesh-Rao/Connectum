import 'package:connectum/core/widgets/app_notification_bell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(int count, VoidCallback onTap) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topRight,
        child: AppNotificationBell(count: count, onPressed: onTap),
      ),
    ),
  );

  testWidgets('no count: only the circle, no number', (tester) async {
    await tester.pumpWidget(host(0, () {}));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(tester.getSize(find.byType(AppNotificationBell)).width, 48);
  });

  testWidgets('a count shows the pill with the number, wider than the circle', (
    tester,
  ) async {
    await tester.pumpWidget(host(7, () {}));
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    expect(
      tester.getSize(find.byType(AppNotificationBell)).width,
      greaterThan(48),
    );
  });

  testWidgets('above 99 reads 99+', (tester) async {
    await tester.pumpWidget(host(100, () {}));
    await tester.pumpAndSettle();
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('switching between the states does not throw and settles', (
    tester,
  ) async {
    await tester.pumpWidget(host(0, () {}));
    await tester.pumpWidget(host(3, () {}));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(host(4, () {}));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(host(0, () {}));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('4'), findsNothing);
  });

  testWidgets(
    'the hit target is at least 48 high and a tap on the count opens',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(5, () => taps++));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(AppNotificationBell)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('5'));
      await tester.tap(find.byIcon(Icons.notifications_none));
      expect(taps, 2);
    },
  );

  testWidgets('the label says how many are unread', (tester) async {
    await tester.pumpWidget(host(2, () {}));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Notifications, 2 unread'), findsOneWidget);
    await tester.pumpWidget(host(0, () {}));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
  });

  testWidgets('with animations disabled the change is instant', (tester) async {
    Widget wrap(int c) => MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: host(c, () {}),
    );
    await tester.pumpWidget(wrap(0));
    await tester.pumpWidget(wrap(9));
    await tester.pump();
    expect(find.text('9'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('geometry: pill 36, bell 30, count circle 24 square', (
    tester,
  ) async {
    await tester.pumpWidget(host(7, () {}));
    await tester.pumpAndSettle();
    final badge = find.ancestor(
      of: find.text('7'),
      matching: find.byType(Container),
    );
    final size = tester.getSize(badge.first);
    expect(size.width, 24);
    expect(size.height, 24);
    final pill = find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxHeight == 36,
    );
    expect(tester.getSize(pill).height, 36);
    final bell = find.ancestor(
      of: find.byIcon(Icons.notifications_none),
      matching: find.byType(Container),
    );
    expect(tester.getSize(bell.first), const Size(30, 30));
  });

  testWidgets('99+ keeps a 24 high rounded count', (tester) async {
    await tester.pumpWidget(host(150, () {}));
    await tester.pumpAndSettle();
    final badge = find.ancestor(
      of: find.text('99+'),
      matching: find.byType(Container),
    );
    final size = tester.getSize(badge.first);
    expect(size.height, 24);
    expect(size.width, greaterThanOrEqualTo(24));
  });

  testWidgets('fits a 56 dp app bar in both states, no overflow', (
    tester,
  ) async {
    Widget bar(int c) => MaterialApp(
      home: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Row(
            children: [
              const Spacer(),
              AppNotificationBell(count: c, onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(bar(0));
    await tester.pumpWidget(bar(12));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppNotificationBell)).height, 48);
    await tester.pumpWidget(bar(0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AppNotificationBell)).height, 48);
  });
}
