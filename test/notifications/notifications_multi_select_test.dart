import 'package:connectum/core/widgets/app_pill_bar.dart';
import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/data/notifications/local_notification_service.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/feed_repository.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/features/notifications/notification_router.dart';
import 'package:connectum/features/notifications/notification_texts.dart';
import 'package:connectum/features/notifications/notifications_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';

class _Router extends Fake implements NotificationRouter {}

class _Notifications extends Fake implements LocalNotificationService {}

class _Connectivity extends Fake implements ConnectivityService {}

class _Conversations extends Fake implements ConversationRepository {
  @override
  final conversations = <Never>[].obs;
}

Map<String, dynamic> _item(
  String id,
  String priority, {
  int ts = 100,
  bool read = false,
}) => {
  'id': id,
  'ts': ts,
  'read': read,
  'priority': priority,
  'resolved': priority == 'resolved',
  'title': id,
  'message': id,
};

Map<String, dynamic> _counts() => {
  'high': 1,
  'medium': 1,
  'low': 1,
  'resolved': 1,
  'unread': 3,
  'total': 3,
};

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
  'counts': _counts(),
  'hasMore': false,
  'notifications': items,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late FeedRepository feed;
  late NotificationsController c;

  setUp(() async {
    socket = FakeSocket()..goOnline();
    feed = FeedRepository(socket, FakeStore(), FakeE2e())..onInit();
    socket.answers['feed.summary'] = _counts();
    socket.answers['feed.list'] = _page([
      _item('h', 'high', ts: 500),
      _item('m', 'medium', ts: 400, read: true),
      _item('l', 'low', ts: 300),
      _item('r', 'resolved', ts: 200, read: true),
    ]);
    await feed.refresh();
    c = NotificationsController(
      feed: feed,
      router: _Router(),
      notifications: _Notifications(),
      connectivity: _Connectivity(),
      conversations: _Conversations(),
    );
  });

  tearDown(() => feed.onClose());

  List<String> ids() => c.visible.map((i) => i.id).toList();
  Set<String> sel() => c.selectedIds.value;

  test('All is the open items and the start state', () {
    expect(sel(), {'all'});
    expect(ids(), ['h', 'm', 'l']);
  });

  test('High then Medium: both on, All off, union shown', () {
    c.toggleChip('high');
    expect(sel(), {'high'});
    c.toggleChip('medium');
    expect(sel(), {'high', 'medium'});
    expect(ids(), ['h', 'm']);
  });

  test('deselecting the last chip returns to All', () {
    c.toggleChip('high');
    c.toggleChip('high');
    expect(sel(), {'all'});
  });

  test('tapping All clears the others', () {
    c.toggleChip('high');
    c.toggleChip('low');
    c.toggleChip('all');
    expect(sel(), {'all'});
  });

  test('Resolved combines as a union with priorities', () {
    c.toggleChip('high');
    c.toggleChip('resolved');
    expect(ids(), ['h', 'r']);
    c.toggleChip('high');
    expect(ids(), ['r']);
  });

  test('Unread only applies on top as AND', () {
    c.toggleChip('medium');
    c.toggleChip('resolved');
    expect(ids(), ['m', 'r']);
    c.isUnreadOnly.value = true;
    expect(ids(), isEmpty);
    c.toggleChip('high');
    expect(ids(), ['h']);
  });

  test('the selection survives a reload and a feed event', () async {
    c.toggleChip('high');
    c.toggleChip('low');
    await feed.refresh();
    feed.onEvent({
      'type': 'sd_event',
      'event': 'feed_item',
      'data': {
        'notification': _item('h2', 'high', ts: 900),
        'counts': _counts(),
      },
    });
    expect(sel(), {'high', 'low'});
    expect(ids(), ['h2', 'h', 'l']);
  });

  test('the selection survives an empty list', () async {
    c.toggleChip('high');
    c.toggleChip('medium');
    socket.answers['feed.list'] = _page([]);
    await feed.refresh();
    expect(ids(), isEmpty);
    expect(sel(), {'high', 'medium'});
  });

  test('nothing matching shows the empty state with the filter text', () async {
    c.toggleChip('resolved');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    feed.items.removeWhere((i) => i.isResolved);
    expect(c.viewState, AppViewState.empty);
    expect(c.emptyMessage, NotificationTexts.emptyFilters);
    c.toggleChip('all');
    expect(c.emptyMessage, NotificationTexts.emptyMessage);
  });

  test('each selected chip is fetched once, with its own priority', () async {
    socket.calls.clear();
    c.toggleChip('high');
    c.toggleChip('medium');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final asked = [
      for (final call in socket.calls)
        if (call.action == 'feed.list') call.args['priority'],
    ];
    expect(asked.toSet(), {'high', 'medium'});
  });

  group('AppPillBar.toggle', () {
    test('exclusive id replaces the set', () {
      expect(AppPillBar.toggle({'a', 'b'}, 'all', exclusiveId: 'all'), {'all'});
    });
    test('without an exclusive id the set can empty', () {
      expect(AppPillBar.toggle({'a'}, 'a'), isEmpty);
    });
  });

  group('AppPillBar widgets', () {
    Finder pill(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(AnimatedContainer),
    );

    Color? fill(WidgetTester t, String label) =>
        ((t.widget<AnimatedContainer>(pill(label)).decoration) as BoxDecoration)
            .color;

    const pills = [
      AppPill(id: 'all', label: 'All'),
      AppPill(id: 'high', label: 'High'),
      AppPill(id: 'low', label: 'Low'),
    ];

    testWidgets('several pills look selected at once', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPillBar.multi(
              pills: pills,
              selectedIds: const {'high', 'low'},
              onToggle: (_) {},
              exclusiveId: 'all',
            ),
          ),
        ),
      );
      final selected = fill(t, 'High');
      expect(fill(t, 'Low'), selected);
      expect(fill(t, 'All'), isNot(selected));
      expect(
        t.getSemantics(find.text('High')).flagsCollection.isSelected,
        isNotNull,
      );
    });

    testWidgets('multi reports the tapped id', (t) async {
      final taps = <String>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPillBar.multi(
              pills: pills,
              selectedIds: const {'all'},
              onToggle: taps.add,
              exclusiveId: 'all',
            ),
          ),
        ),
      );
      await t.tap(find.text('Low'));
      expect(taps, ['low']);
    });

    testWidgets('single-select mode is unchanged', (t) async {
      final taps = <int>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPillBar(
              pills: const [
                AppPill(label: 'A'),
                AppPill(label: 'B'),
              ],
              selected: 1,
              onSelected: taps.add,
            ),
          ),
        ),
      );
      expect(fill(t, 'A'), isNot(fill(t, 'B')));
      await t.tap(find.text('A'));
      expect(taps, [0]);
    });
  });
}
