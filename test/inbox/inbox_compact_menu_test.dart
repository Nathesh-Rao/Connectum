import 'package:connectum/features/tickets/models/card_menu.dart';
import 'package:connectum/features/tickets/widgets/record_menu_rows.dart';
import 'package:connectum/core/widgets/app_anchored_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';

const _items = [
  CardMenuItem('act-send', 'Send', Icons.send_rounded),
  CardMenuItem('act-status', 'Update status', Icons.sync_alt_rounded),
  CardMenuItem(CardMenuItem.history, 'History', Icons.history_rounded),
];

Finder get card => find.ancestor(
  of: find.text('Send'),
  matching: find.byType(SingleChildScrollView),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;
  late List<String> picked;

  setUp(() {
    rig = InboxRig();
    picked = [];
    addTearDown(rig.dispose);
  });

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 800),
    double scale = 1,
    Alignment at = Alignment.topRight,
    List<CardMenuItem> items = _items,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(
            child: Align(
              alignment: at,
              child: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => AppAnchoredPopup.show(
                    context,
                    label: 'Record menu',
                    builder: (popup) => RecordMenuRows(
                      tickets: rig.tickets,
                      recordId: null,
                      isCompact: true,
                      itemsFor: (_) => items,
                      onPick: (item) {
                        Navigator.of(popup).pop();
                        picked.add(item.id);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
  }

  testWidgets('width wraps inside 168..220 and under 60 percent', (
    tester,
  ) async {
    await open(tester);
    final w = tester.getSize(card).width;
    expect(w, inInclusiveRange(168, 220));
    expect(w, lessThanOrEqualTo(390 * 0.6));
  });

  testWidgets('rows are at least 44 px and icons share one left edge', (
    tester,
  ) async {
    await open(tester);
    for (final t in ['Send', 'Update status', 'History']) {
      final row = find.ancestor(
        of: find.text(t),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
    }
    final lefts = {
      for (final i in [
        Icons.send_rounded,
        Icons.sync_alt_rounded,
        Icons.history_rounded,
      ])
        tester.getTopLeft(find.byIcon(i)).dx,
    };
    expect(lefts.length, 1);
    final cardLeft = tester.getTopLeft(card).dx;
    expect(lefts.first - cardLeft, greaterThanOrEqualTo(12));
  });

  testWidgets('no divider between normal rows, one above a danger row', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(Divider), findsNothing);
    await tester.tapAt(const Offset(4, 400));
    await tester.pumpAndSettle();
    await open(
      tester,
      items: const [
        CardMenuItem('act-send', 'Send', Icons.send_rounded),
        CardMenuItem(
          CardMenuItem.delete,
          'Delete',
          Icons.delete_rounded,
          isDanger: true,
        ),
      ],
    );
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('opens down with the right edge on the button', (tester) async {
    await open(tester);
    final button = tester.getRect(find.byIcon(Icons.more_horiz));
    final c = tester.getRect(card);
    expect(c.top, greaterThanOrEqualTo(button.bottom));
    expect(c.right, closeTo(button.right + 4, 12));
  });

  testWidgets('flips up near the bottom and never covers the button', (
    tester,
  ) async {
    await open(tester, at: Alignment.bottomRight);
    final button = tester.getRect(find.byIcon(Icons.more_horiz));
    final c = tester.getRect(card);
    expect(c.bottom, lessThanOrEqualTo(button.top));
  });

  testWidgets('stays on screen at 320 px', (tester) async {
    await open(tester, size: const Size(320, 640), at: Alignment.topLeft);
    final c = tester.getRect(card);
    expect(c.left, greaterThanOrEqualTo(0));
    expect(c.right, lessThanOrEqualTo(320));
    expect(c.width, lessThanOrEqualTo(320 * 0.6));
  });

  testWidgets('text scale 1.5 does not overflow', (tester) async {
    await open(tester, size: const Size(320, 640), scale: 1.5);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(card).width, lessThanOrEqualTo(220));
  });

  testWidgets('semantics list the items in order', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    for (final t in ['Send', 'Update status', 'History']) {
      expect(find.bySemanticsLabel(t), findsOneWidget);
    }
    handle.dispose();
  });

  testWidgets('closes on outside tap and on back', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(4, 600));
    await tester.pumpAndSettle();
    expect(find.text('Send'), findsNothing);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Send'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Send'), findsNothing);
    expect(picked, isEmpty);
  });

  testWidgets('every item reports its own id and closes the menu', (
    tester,
  ) async {
    for (final item in _items) {
      await open(tester);
      await tester.tap(find.text(item.label));
      await tester.pumpAndSettle();
      expect(picked.last, item.id);
      expect(find.text(item.label), findsNothing);
    }
    expect(picked, [for (final i in _items) i.id]);
  });

  testWidgets('golden: the compact menu', (tester) async {
    await open(
      tester,
      size: const Size(390, 300),
      items: const [
        ..._items,
        CardMenuItem(
          CardMenuItem.delete,
          'Delete',
          Icons.delete_outline_rounded,
          isDanger: true,
        ),
      ],
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/inbox_compact_menu.png'),
    );
  });
}
