import 'package:connectum/core/widgets/app_pill_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows labels and counts, reports the tapped pill', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => AppPillBar(
            pills: const [
              AppPill(label: 'All'),
              AppPill(label: 'High', count: 3, kind: AppPillKind.accent),
              AppPill(label: 'Low', count: 120, kind: AppPillKind.calm),
            ],
            selected: selected,
            onSelected: (i) => setState(() => selected = i),
          ),
        ),
      ),
    );
    expect(find.text('All'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });

  testWidgets('the selected pill is filled, the others tinted', (tester) async {
    await tester.pumpWidget(
      _host(
        AppPillBar(
          pills: const [
            AppPill(label: 'A', kind: AppPillKind.accent),
            AppPill(label: 'B', kind: AppPillKind.sand),
          ],
          selected: 1,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    Color fillOf(String label) {
      final box = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    expect(fillOf('A'), AppPillKind.accent.tint);
    expect(fillOf('B'), AppPillKind.sand.fill);
  });

  testWidgets('a long set scrolls sideways without overflow', (tester) async {
    await tester.pumpWidget(
      _host(
        AppPillBar(
          pills: [
            for (var i = 0; i < 12; i++) AppPill(label: 'Pill number $i'),
          ],
          selected: 0,
          onSelected: (_) {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
