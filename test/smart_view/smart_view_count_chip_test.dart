import 'package:connectum/features/smart_view/widgets/smart_view_count_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget chip, {double width = 390}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: width,
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'A very long structure name that must give way first',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          chip,
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('total state: "Total" and the number, semantics', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(_host(const SmartViewCountChip(total: 120)));
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.bySemanticsLabel('Total records 120'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('filtered state: Showing 3 of 1,200, then a quick swap', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(_host(const SmartViewCountChip(total: 1200, shown: 3)));
    expect(find.text('Showing'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('of 1,200'), findsOneWidget);
    expect(find.bySemanticsLabel('Showing 3 of 1,200 records'), findsOneWidget);
    await t.pumpWidget(_host(const SmartViewCountChip(total: 1200, shown: 4)));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('3'), findsNothing);
    expect(find.text('4'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tight space: the chip keeps its size, the title shrinks', (
    t,
  ) async {
    await t.pumpWidget(_host(const SmartViewCountChip(total: 120), width: 390));
    final wide = t.getSize(find.byType(SmartViewCountChip));
    await t.pumpWidget(_host(const SmartViewCountChip(total: 120), width: 200));
    expect(t.getSize(find.byType(SmartViewCountChip)), wide);
    expect(t.takeException(), isNull);
  });
}
