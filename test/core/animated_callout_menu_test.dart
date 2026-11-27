import 'package:connectum/core/widgets/animated_callout_menu.dart';
import 'package:connectum/core/widgets/callout_menu/callout_painter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _items = [
  MenuItem<String>(label: 'Send', icon: Icons.send_rounded, value: 'send'),
  MenuItem<String>(
    label: 'Update status',
    icon: Icons.sync_alt_rounded,
    value: 'status',
  ),
  MenuItem<String>(
    label: 'History',
    icon: Icons.history_rounded,
    value: 'history',
  ),
];

final _painter = find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is CalloutPainter,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? result;
  late bool isDone;

  Future<void> pumpHost(
    WidgetTester t, {
    Size size = const Size(320, 640),
    Alignment at = Alignment.topRight,
    bool isStill = false,
    double scale = 1,
    List<MenuItem<String>> items = _items,
    ValueListenable<List<MenuItem<String>>>? live,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    result = null;
    isDone = false;
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: isStill,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: at,
            child: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.more_horiz),
                onPressed: () async {
                  final anchor = AnimatedCalloutMenu.anchorOf(context)!;
                  result = await AnimatedCalloutMenu.show<String>(
                    context,
                    anchor,
                    items,
                    label: 'Record menu',
                    live: live,
                  );
                  isDone = true;
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pumpAndSettle();
  }

  double opacityOf(WidgetTester t, String text) => t
      .widget<Opacity>(
        find
            .ancestor(of: find.text(text), matching: find.byType(Opacity))
            .first,
      )
      .opacity;

  CalloutFrame frame(WidgetTester t) =>
      (t.widget<CustomPaint>(_painter).painter! as CalloutPainter).frame;

  testWidgets('Send comes out first, then the stack, one row after another', (
    t,
  ) async {
    await pumpHost(t);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pump();
    final firstSeen = <String, int>{};
    for (var ms = 0; ms <= 640; ms += 16) {
      await t.pump(const Duration(milliseconds: 16));
      for (final i in _items) {
        if (opacityOf(t, i.label) > 0.01) {
          firstSeen.putIfAbsent(i.label, () => ms);
        }
      }
    }
    expect(firstSeen.keys, hasLength(3));
    expect(firstSeen['Send']!, lessThan(firstSeen['Update status']!));
    expect(firstSeen['Update status']!, lessThan(firstSeen['History']!));
    await t.pumpAndSettle();
    for (final i in _items) {
      expect(opacityOf(t, i.label), 1);
    }
  });

  testWidgets('the tail grows with the first row, the cards then merge', (
    t,
  ) async {
    await pumpHost(t);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    var f = frame(t);
    expect(f.tailGrow, greaterThan(0));
    expect(f.tailGrow, lessThan(1));
    expect(f.join, 0);
    await t.pump(const Duration(milliseconds: 220));
    f = frame(t);
    expect(f.join, 0, reason: 'the cards are still apart');
    expect(f.cards[1].top, greaterThan(f.cards[0].bottom));
    await t.pumpAndSettle();
    f = frame(t);
    expect(f.join, 1);
    expect(f.tailGrow, closeTo(1, 1e-9));
  });

  test('the tail and the panel are one outline, on top or flipped', () {
    const body = Rect.fromLTWH(0, 10, 190, 140);
    Path path(double grow, bool isUp) => calloutPath(
      rect: isUp ? const Rect.fromLTWH(0, 0, 190, 140) : body,
      radius: 12,
      tipX: 95,
      apexY: isUp ? 150 : 0,
      grow: grow,
      isUp: isUp,
      boxHeight: 150,
    );
    expect(path(1, false).getBounds().top, closeTo(0, 0.01));
    expect(path(0, false).getBounds().top, closeTo(10, 0.01));
    expect(path(1, true).getBounds().bottom, closeTo(150, 0.01));
    expect(path(0, true).getBounds().bottom, closeTo(140, 0.01));
    expect(path(1, false).contains(const Offset(95, 5)), isTrue);
    expect(path(1, false).contains(const Offset(10, 5)), isFalse);
  });

  testWidgets('a tap returns the row value and closes the menu', (t) async {
    await pumpHost(t);
    await open(t);
    await t.tap(find.text('Update status'));
    await t.pumpAndSettle();
    expect(isDone, isTrue);
    expect(result, 'status');
    expect(find.text('Update status'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('tap outside, back and Escape close it with no value', (t) async {
    await pumpHost(t);
    await open(t);
    await t.tapAt(const Offset(10, 600));
    await t.pumpAndSettle();
    expect((isDone, result), (true, null));
    expect(find.text('Send'), findsNothing);

    isDone = false;
    await open(t);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect((isDone, result), (true, null));
    expect(find.text('Send'), findsNothing);

    isDone = false;
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect((isDone, result), (true, null));
    expect(find.text('Send'), findsNothing);
  });

  testWidgets('closing plays the opening backwards', (t) async {
    await pumpHost(t);
    await open(t);
    await t.tapAt(const Offset(10, 600));
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    expect(frame(t).join, lessThan(1));
    await t.pump(const Duration(milliseconds: 300));
    expect(frame(t).join, 0);
    await t.pumpAndSettle();
    expect(find.text('Send'), findsNothing);
  });

  testWidgets('a tap during the opening still picks the first row', (t) async {
    await pumpHost(t);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(result, 'send');
  });

  testWidgets('at the bottom it flips upward and stays on screen', (t) async {
    await pumpHost(t, at: Alignment.bottomRight);
    await open(t);
    final screen = Offset.zero & const Size(320, 640);
    for (final i in _items) {
      final r = t.getRect(find.text(i.label));
      expect(screen.contains(r.topLeft), isTrue, reason: i.label);
      expect(screen.contains(r.bottomRight), isTrue, reason: i.label);
    }
    final anchor = t.getRect(find.byIcon(Icons.more_horiz));
    expect(t.getRect(find.text('History')).bottom, lessThan(anchor.top));
    expect(
      t.getRect(find.text('Send')).top,
      lessThan(t.getRect(find.text('History')).top),
      reason: 'the order of the rows does not change',
    );
    await t.tap(find.text('History'));
    await t.pumpAndSettle();
    expect(result, 'history');
  });

  testWidgets('opens under the anchor when there is room', (t) async {
    await pumpHost(t);
    await open(t);
    final anchor = t.getRect(find.byIcon(Icons.more_horiz));
    expect(t.getRect(find.text('Send')).top, greaterThan(anchor.bottom));
  });

  testWidgets('reduced motion: a plain fade, the panel is already one', (
    t,
  ) async {
    await pumpHost(t, isStill: true);
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));
    final f = frame(t);
    expect(f.join, 1);
    expect(f.tailGrow, closeTo(1, 1e-9));
    for (final i in _items) {
      expect(find.text(i.label), findsOneWidget);
    }
    await t.pumpAndSettle();
    await t.tap(find.text('History'));
    await t.pumpAndSettle();
    expect(result, 'history');
    expect(t.takeException(), isNull);
  });

  for (final scale in [1.0, 1.5, 3.0]) {
    testWidgets('320 px, text x$scale: no overflow, inside the screen', (
      t,
    ) async {
      await pumpHost(t, scale: scale, at: Alignment.topLeft);
      await open(t);
      expect(t.takeException(), isNull);
      final screen = Offset.zero & const Size(320, 640);
      for (final i in _items) {
        final r = t.getRect(find.text(i.label));
        expect(screen.contains(r.topLeft), isTrue, reason: i.label);
        expect(screen.contains(r.bottomRight), isTrue, reason: i.label);
      }
    });
  }

  testWidgets('a row that is off shows why and does nothing; a note is inert', (
    t,
  ) async {
    await pumpHost(
      t,
      items: const [
        MenuItem<String>(
          label: 'Send',
          icon: Icons.send_rounded,
          value: 'send',
          isEnabled: false,
          why: 'Only the person it is with can do this.',
        ),
        MenuItem<String>.note('Loading…'),
        MenuItem<String>(
          label: 'Delete',
          icon: Icons.delete_rounded,
          value: 'delete',
          isDanger: true,
          hasDividerAbove: true,
        ),
      ],
    );
    await open(t);
    expect(
      find.text('Only the person it is with can do this.'),
      findsOneWidget,
    );
    expect(find.byType(Divider), findsOneWidget);
    await t.tap(find.text('Send'));
    await t.tap(find.text('Loading…'));
    await t.pumpAndSettle();
    expect(isDone, isFalse);
    expect(find.text('Send'), findsOneWidget);
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(result, 'delete');
  });

  testWidgets('live rows replace the list while the menu is open', (t) async {
    final live = ValueNotifier<List<MenuItem<String>>>(const [
      MenuItem<String>.note('Loading…'),
    ]);
    addTearDown(live.dispose);
    await pumpHost(t, live: live, items: live.value);
    await open(t);
    expect(find.text('Loading…'), findsOneWidget);
    live.value = _items;
    await t.pumpAndSettle();
    expect(find.text('Loading…'), findsNothing);
    expect(find.text('History'), findsOneWidget);
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(result, 'send');
  });

  testWidgets('the menu and every row are in the semantics tree', (t) async {
    final handle = t.ensureSemantics();
    await pumpHost(t);
    await open(t);
    expect(find.bySemanticsLabel('Record menu'), findsWidgets);
    for (final i in _items) {
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
