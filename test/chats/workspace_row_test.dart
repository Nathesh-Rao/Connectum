import 'package:connectum/features/chats/widgets/workspace_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('no PINNED label, a circle tile, the subtitle stays', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkspaceRow(onTap: () {})),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My Work Space'), findsOneWidget);
    expect(find.text('PINNED'), findsNothing);
    expect(find.textContaining("Type '#'"), findsOneWidget);
    final tile = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.shape == BoxShape.circle);
    expect(tile, isNotEmpty);
  });
}
