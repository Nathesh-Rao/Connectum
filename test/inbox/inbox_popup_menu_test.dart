import 'package:connectum/core/widgets/animated_callout_menu.dart';
import 'package:connectum/core/widgets/callout_menu/callout_painter.dart';
import 'package:connectum/features/inbox/widgets/inbox_card.dart';
import 'package:connectum/features/tickets/models/card_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _items = [
  CardMenuItem('act-send', 'Send', Icons.send_rounded),
  CardMenuItem('act-status', 'Update status', Icons.sync_alt_rounded),
  CardMenuItem(CardMenuItem.history, 'History', Icons.history_rounded),
];

final _painter = find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is CalloutPainter,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> picked;

  setUp(() => picked = []);

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
                  onPressed: () async {
                    final item = await AnimatedCalloutMenu.show<CardMenuItem>(
                      context,
                      AnimatedCalloutMenu.anchorOf(context)!,
                      InboxMenu.rowsFor(_items),
                      label: 'Record menu',
                    );
                    if (item != null) picked.add(item.id);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder text(String s) => find.text(s);

  double opacityOf(WidgetTester t, String s) => t
      .widget<Opacity>(
        find.ancestor(of: text(s), matching: find.byType(Opacity)).first,
      )
      .opacity;

  double join(WidgetTester t) =>
      (t.widget<CustomPaint>(_painter).painter! as CalloutPainter).frame.join;

  testWidgets('the items come out one after another, then merge', (t) async {
    await pumpMenu(t);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(opacityOf(t, 'Send'), greaterThan(0));
    expect(opacityOf(t, 'Update status'), 0);
    expect(opacityOf(t, 'History'), 0);
    await t.pump(const Duration(milliseconds: 200));
    expect(opacityOf(t, 'Update status'), greaterThan(opacityOf(t, 'History')));
    expect(join(t), 0, reason: 'the cards are apart before the merge');
    await t.pumpAndSettle();
    expect(join(t), 1);
    for (final i in _items) {
      expect(opacityOf(t, i.label), 1);
    }
  });

  testWidgets('closing is the same sequence backwards', (t) async {
    await pumpMenu(t);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(4, 700));
    await t.pump();
    // First the panel splits into separate cards...
    await t.pump(const Duration(milliseconds: 60));
    expect(join(t), lessThan(1));
    for (final i in _items) {
      expect(opacityOf(t, i.label), greaterThan(0.9), reason: i.label);
    }
    // ...then the last card goes first, the first card last.
    await t.pump(const Duration(milliseconds: 260));
    expect(opacityOf(t, 'History'), lessThan(opacityOf(t, 'Update status')));
    expect(
      opacityOf(t, 'Update status'),
      lessThanOrEqualTo(opacityOf(t, 'Send')),
    );
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
    expect(picked, isEmpty);
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
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    await t.tap(text('Send'));
    await t.pumpAndSettle();
    expect(picked.last, 'act-send');
    expect(picked.length, 4);
  });

  testWidgets('reduced motion: a plain fade, the cards are one panel', (
    t,
  ) async {
    await pumpMenu(t, isStill: true);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    expect(join(t), 1);
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
}
