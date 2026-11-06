import 'package:connectum/core/theme/app_spacing.dart';
import 'package:connectum/core/theme/app_tones.dart';
import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:connectum/features/notifications/notification_style.dart';
import 'package:connectum/features/notifications/notification_texts.dart';
import 'package:connectum/features/notifications/widgets/feed_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FeedItem _item({
  String priority = 'low',
  bool isRead = false,
  String title = 'Ticket TK-1',
  String message = 'Status changed',
  String? category,
}) => FeedItem(
  id: 'a',
  priority: priority,
  isRead: isRead,
  title: title,
  message: message,
  category: category,
  ts: DateTime.now().millisecondsSinceEpoch,
);

Future<void> _pump(
  WidgetTester tester,
  FeedItem item, {
  void Function(FeedTileMenu)? onMenu,
  VoidCallback? onTap,
  double width = 320,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: FeedTile(
          item: item,
          readText: (i) => Future.value(i.message),
          onTap: onTap ?? () {},
          onMenu: onMenu ?? (_) {},
          onDismissed: () {},
        ),
      ),
    ),
  ),
);

Finder _circle() => find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
      (w.constraints?.maxWidth ?? 0) == 44,
);

void main() {
  testWidgets('shows the mapped icon in its colour on a tint', (tester) async {
    await _pump(tester, _item(title: 'Ticket TK-1'));
    final icon = tester.widget<Icon>(
      find.byIcon(Icons.confirmation_number_rounded),
    );
    expect(icon.color, AppTones.purple.solid);
    expect(icon.size, 22);
    final circle = tester.widget<Container>(_circle());
    expect((circle.decoration! as BoxDecoration).color, AppTones.purple.tint);
  });

  testWidgets('priority pill: high, medium, resolved shown, low hidden', (
    tester,
  ) async {
    await _pump(tester, _item(priority: 'high'));
    expect(find.text(NotificationTexts.priorityHigh), findsOneWidget);
    await _pump(tester, _item(priority: 'medium'));
    expect(find.text(NotificationTexts.priorityMedium), findsOneWidget);
    await _pump(tester, _item(priority: 'resolved'));
    expect(find.text(NotificationTexts.priorityResolved), findsOneWidget);
    await _pump(tester, _item(priority: 'low'));
    expect(find.text(NotificationTexts.priorityLow), findsNothing);
  });

  testWidgets('unread has a dot and a heavier title', (tester) async {
    await _pump(tester, _item(isRead: false));
    final unread = tester.widget<Text>(find.text('Ticket TK-1'));
    expect(unread.style!.fontWeight, FontWeight.w600);
    final dots = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
          (w.constraints?.maxWidth ?? 0) < 20,
    );
    expect(dots, findsOneWidget);

    await _pump(tester, _item(isRead: true));
    final read = tester.widget<Text>(find.text('Ticket TK-1'));
    expect(read.style!.fontWeight, FontWeight.w500);
    expect(dots, findsNothing);
  });

  testWidgets('long text is clipped without overflow', (tester) async {
    final long = ('word ' * 120).trim();
    await _pump(
      tester,
      _item(title: long, message: long, priority: 'high'),
      width: 280,
    );
    expect(tester.takeException(), isNull);
    final texts = tester.widgetList<Text>(find.text(long)).toList();
    expect(texts.map((t) => t.maxLines), containsAll([2, 3]));
  });

  testWidgets('three dots open the actions and report the pick', (
    tester,
  ) async {
    FeedTileMenu? picked;
    await _pump(tester, _item(), onMenu: (m) => picked = m);
    await tester.tap(find.byTooltip(NotificationTexts.menu));
    await tester.pumpAndSettle();
    expect(find.text(NotificationTexts.markRead), findsOneWidget);
    expect(find.text(NotificationTexts.resolve), findsOneWidget);
    expect(find.text(NotificationTexts.dismiss), findsOneWidget);
    await tester.tap(find.text(NotificationTexts.resolve));
    await tester.pumpAndSettle();
    expect(picked, FeedTileMenu.resolve);
  });

  testWidgets('tapping the row calls onTap', (tester) async {
    var taps = 0;
    await _pump(tester, _item(), onTap: () => taps++);
    await tester.tap(find.text('Status changed'));
    expect(taps, 1);
  });

  testWidgets('the priority pill hugs its text', (tester) async {
    await _pump(tester, _item(priority: 'high'));
    final pill = find.ancestor(
      of: find.text(NotificationTexts.priorityHigh),
      matching: find.byType(Container),
    );
    final size = tester.getSize(pill.first);
    expect(size.height, AppSpacing.priorityPillHeight);
    expect(size.width, lessThan(80));
  });

  testWidgets('the unread dot and the action text use the tile colour', (
    tester,
  ) async {
    final item = FeedItem(
      id: 'a',
      title: 'Ticket TK-1',
      message: 'Status changed',
      actionType: 'tickets',
      actionLabel: 'View ticket',
      chatId: 'x',
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    await _pump(tester, item);
    final color = styleFor(item).color;
    final dot = tester.widget<Container>(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
            (w.constraints?.maxWidth ?? 0) < 20,
      ),
    );
    expect((dot.decoration! as BoxDecoration).color, color);
    final action = find.text('View ticket');
    if (action.evaluate().isNotEmpty) {
      expect(tester.widget<Text>(action).style!.color, color);
    }
  });

  testWidgets('the swipe background uses the tile colours', (tester) async {
    final item = _item();
    await _pump(tester, item);
    final style = styleFor(item);
    final dismissible = tester.widget<Dismissible>(find.byType(Dismissible));
    expect(dismissible.background, isA<FeedSwipeBackground>());
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: dismissible.background)),
    );
    final box = tester.widget<Container>(find.byType(Container).first);
    expect(box.color, style.tintStrong);
    expect(
      tester.widget<Text>(find.text('Dismiss')).style!.color,
      style.strong,
    );
    expect(tester.widget<Icon>(find.byIcon(Icons.close)).color, style.strong);
  });
}
