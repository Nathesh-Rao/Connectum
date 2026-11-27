import 'package:connectum/core/widgets/app_anchored_popup.dart';
import 'package:connectum/features/tickets/models/card_menu.dart';
import 'package:connectum/features/tickets/widgets/record_menu_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';

const _items = [
  CardMenuItem('act-send', 'Send', Icons.send_rounded),
  CardMenuItem('act-status', 'Update status', Icons.sync_alt_rounded),
  CardMenuItem(CardMenuItem.history, 'History', Icons.history_rounded),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;
  late List<String> picked;

  setUp(() {
    rig = InboxRig();
    picked = [];
    addTearDown(rig.dispose);
  });

  Future<void> pumpMenu(WidgetTester t, {bool isStill = false}) async {
    t.view.physicalSize = const Size(390, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: isStill),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(
            child: Align(
              alignment: Alignment.topRight,
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
                      itemsFor: (_) => _items,
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
  }

  Finder text(String s) => find.text(s);
  final surface = find.ancestor(
    of: find.text('Send'),
    matching: find.byType(SingleChildScrollView),
  );

  Future<Map<String, double>> fullWidths(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pumpAndSettle();
    final w = {
      for (final i in _items) i.label: t.getRect(text(i.label)).width,
      'height': t.getSize(surface).height,
    };
    await t.tapAt(const Offset(4, 700));
    await t.pumpAndSettle();
    expect(text('Send'), findsNothing);
    return w;
  }

  testWidgets('the items come out one after another, then merge', (t) async {
    await pumpMenu(t);
    final full = await fullWidths(t);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pump();

    double? lastHeight;
    final samples = <int, List<double>>{};
    for (final ms in [30, 50, 50, 50, 50]) {
      await t.pump(Duration(milliseconds: ms));
      final at = samples.length;
      samples[at] = [
        for (final i in _items) t.getRect(text(i.label)).width / full[i.label]!,
      ];
      lastHeight = t.getSize(surface).height;
    }
    // Early on the first card is further out than the second and the third.
    final early = samples[1]!;
    expect(early[0], greaterThan(early[1]));
    expect(early[1], greaterThan(early[2]));
    // The cards are apart (the menu is taller than its merged height) before
    // the merge.
    expect(lastHeight, greaterThan(full['height']! + 4));

    await t.pump(const Duration(milliseconds: 60));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.getSize(surface).height, closeTo(full['height']!, 0.5));
    for (final i in _items) {
      expect(t.getRect(text(i.label)).width, closeTo(full[i.label]!, 0.5));
    }
  });

  testWidgets('closing is the same sequence backwards', (t) async {
    await pumpMenu(t);
    final full = await fullWidths(t);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(4, 700));
    await t.pump();
    // First the surface splits into separate cards...
    await t.pump(const Duration(milliseconds: 60));
    expect(t.getSize(surface).height, greaterThan(full['height']! + 1));
    for (final i in _items) {
      expect(
        t.getRect(text(i.label)).width / full[i.label]!,
        greaterThan(0.9),
        reason: '${i.label} is still out',
      );
    }
    // ...then the last card goes first, the first card last.
    await t.pump(const Duration(milliseconds: 150));
    final mid = [
      for (final i in _items) t.getRect(text(i.label)).width / full[i.label]!,
    ];
    expect(mid[2], lessThan(mid[1]));
    expect(mid[2], lessThan(mid[0]));
    await t.pump(const Duration(milliseconds: 110));
    final late = [
      for (final i in _items) t.getRect(text(i.label)).width / full[i.label]!,
    ];
    expect(late[1], lessThan(late[0]));
    expect(late[2], lessThan(late[1]));
    await t.pumpAndSettle();
    expect(text('Send'), findsNothing);
    expect(picked, isEmpty);
  });

  testWidgets('back closes it the same way', (t) async {
    await pumpMenu(t);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    expect(text('Send'), findsOneWidget);
    await t.pumpAndSettle();
    expect(text('Send'), findsNothing);
  });

  testWidgets('the items still take taps, also while they fly', (t) async {
    await pumpMenu(t);
    for (final item in _items) {
      await t.tap(find.byIcon(Icons.more_horiz));
      await t.pumpAndSettle();
      await t.tap(text(item.label));
      await t.pumpAndSettle();
      expect(picked.last, item.id);
      expect(text(item.label), findsNothing);
    }
    // Tapped before the merge is done.
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    await t.tap(text('Send'));
    await t.pumpAndSettle();
    expect(picked.last, 'act-send');
    expect(picked.length, 4);
  });

  testWidgets('reduced motion: a plain fade, the cards are one surface', (
    t,
  ) async {
    await pumpMenu(t, isStill: true);
    final full = await fullWidths(t);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    expect(t.getSize(surface).height, closeTo(full['height']!, 0.5));
    for (final i in _items) {
      expect(t.getRect(text(i.label)).width, closeTo(full[i.label]!, 0.5));
    }
    await t.pumpAndSettle();
    await t.tap(text('History'));
    await t.pumpAndSettle();
    expect(picked, ['history']);
  });

  testWidgets('the menu and every item are in the semantics tree', (t) async {
    final handle = t.ensureSemantics();
    await pumpMenu(t);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Record menu'), findsWidgets);
    for (final i in _items) {
      expect(find.bySemanticsLabel(i.label), findsOneWidget);
      expect(
        t.getSemantics(find.bySemanticsLabel(i.label)),
        matchesSemantics(
          label: i.label,
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
    }
    handle.dispose();
  });

  test('the timeline: items one after another, the merge last', () {
    double enter(int i, double ms) => AppPopupTiming.enter(i, ms / 380);
    expect(enter(0, 0), 0);
    expect(enter(1, 40), 0);
    expect(enter(0, 40), greaterThan(0));
    expect(enter(1, 90), greaterThan(0));
    expect(enter(2, 90), 0);
    expect(enter(2, 380), closeTo(1, 1e-9));
    expect(AppPopupTiming.merge(250 / 380), 0);
    expect(AppPopupTiming.merge(1), 1);
    for (final i in [0, 1, 2]) {
      expect(enter(i, 280), closeTo(1, 0.1));
    }
  });
}
