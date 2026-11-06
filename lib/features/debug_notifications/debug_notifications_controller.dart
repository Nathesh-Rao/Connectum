import 'package:get/get.dart';

import '../../core/widgets/app_notices.dart';
import '../../data/notifications/local_notification_service.dart';
import '../../data/repositories/feed_repository.dart';
import '../notifications/models/feed_item.dart';

/// Injects sample `feed_item` / `feed_removed` / `feed_changed` events into
/// the feed, as if the server had sent them, and fires local notifications.
/// Debug builds only (see "Before release" in CLAUDE.md).
class DebugNotificationsController extends GetxController {
  DebugNotificationsController({
    required this.feed,
    required this.notifications,
  });

  final FeedRepository feed;
  final LocalNotificationService notifications;

  int _seq = 0;
  String? _lastId;
  int _coalesced = 1;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  void _send(String event, Map<String, dynamic> data) =>
      feed.onEvent({'type': 'sd_event', 'event': event, 'data': data});

  Map<String, dynamic> _counts() => {
    'high': 0,
    'medium': 0,
    'low': 0,
    'resolved': 0,
    'unread': feed.unread.value + 1,
    'total': feed.items.length + 1,
  };

  void _item(Map<String, dynamic> json) {
    _lastId = '${json['id']}';
    _send('feed_item', {'notification': json, 'counts': _counts()});
  }

  String get _id => 'debug-${++_seq}';

  void plainMessage() => _item({
    'id': _id,
    'priority': 'medium',
    'category': 'messages',
    'title': 'Sam W',
    'message': 'Are we still on for the demo?',
    'ts': _now,
    'icon': 'chat',
    'read': false,
    'resolved': false,
    'actionType': 'open_chat',
    'actionLabel': 'Open chat',
    'chatId': 'user-sam1',
    'count': 1,
    'from': 'sam1',
  });

  void mention() => _item({
    'id': _id,
    'priority': 'medium',
    'category': 'messages',
    'title': 'Sam W mentioned you',
    'message': '@me please review the numbers',
    'ts': _now,
    'icon': 'alternate_email',
    'actionType': 'open_message',
    'actionLabel': 'Open message',
    'chatId': 'room-general-team',
    'ref': {'messageId': '1'},
    'count': 1,
    'from': 'sam1',
  });

  void groupMessage() => _item({
    'id': _id,
    'priority': 'low',
    'category': 'messages',
    'title': 'Team',
    'message': 'Ana: lunch at one?',
    'ts': _now,
    'icon': 'group',
    'actionType': 'open_chat',
    'actionLabel': 'Open group',
    'chatId': 'room-general-team',
    'count': 1,
    'from': 'ana',
  });

  void approval() => _item({
    'id': _id,
    'priority': 'high',
    'category': 'approvals',
    'title': 'Approval needed',
    'message': 'Leave request from Priya R',
    'ts': _now,
    'icon': 'fact_check',
    'actionType': 'approvals',
    'actionLabel': 'Review approval',
    'count': 1,
  });

  void task() => _item({
    'id': _id,
    'priority': 'medium',
    'category': 'system',
    'title': 'New task from Dev',
    'message': 'Update the onboarding checklist',
    'ts': _now,
    'icon': 'task_alt',
    'count': 1,
  });

  /// The envelope is not real, so the device cannot open it: the tile and the
  /// notification show the encrypted fallback.
  void e2eEnvelope() => _item({
    'id': _id,
    'priority': 'medium',
    'category': 'messages',
    'title': 'Sam W',
    'message': 'e2e1:not-a-real-envelope',
    'e2e': true,
    'ts': _now,
    'icon': 'chat',
    'actionType': 'open_chat',
    'actionLabel': 'Open chat',
    'chatId': 'user-sam1',
    'count': 1,
    'from': 'sam1',
  });

  /// The same id three times with a rising count: one tile, one banner.
  void coalesced() {
    if (_coalesced >= 3 || _lastId == null || !_lastId!.startsWith('co-')) {
      _coalesced = 0;
      _lastId = 'co-${++_seq}';
    }
    _coalesced++;
    _send('feed_item', {
      'notification': {
        'id': _lastId,
        'priority': 'medium',
        'category': 'messages',
        'title': 'Group chat',
        'message': 'Message number $_coalesced',
        'ts': _now,
        'icon': 'group',
        'actionType': 'open_chat',
        'actionLabel': 'Open group',
        'chatId': 'room-general-team',
        'count': _coalesced,
        'from': 'sam1',
      },
      'counts': _counts(),
    });
  }

  /// The last injected item resolved.
  void resolveLast() {
    final id = _lastId;
    final item = feed.items.firstWhereOrNull((i) => i.id == id);
    if (item == null) return;
    _send('feed_item', {
      'notification': {
        'id': item.id,
        'priority': 'resolved',
        'category': item.category,
        'title': item.title,
        'message': item.message,
        'ts': item.ts,
        'icon': item.icon,
        'read': true,
        'resolved': true,
        'resolvedTs': _now,
      },
      'counts': _counts(),
    });
  }

  void removeLast() {
    final id = _lastId;
    if (id == null) return;
    _send('feed_removed', {
      'ids': [id],
      'counts': {'unread': 0},
    });
  }

  void readLast() {
    final id = _lastId;
    if (id == null) return;
    _send('feed_changed', {
      'ids': [id],
      'read': true,
      'counts': {'unread': 0},
    });
  }

  /// A real system notification for a sample item through the same `show()`
  /// path as live items, whatever the rules say. The result is logged
  /// (`notifyflow:`) and told.
  Future<void> fireLocal() async {
    await notifications.refreshPermission();
    final isShown = await notifications.show(
      FeedItem(
        id: _id,
        priority: 'high',
        category: 'messages',
        title: 'Sam W',
        message: 'Local notification test',
        ts: _now,
        actionType: 'open_chat',
        actionLabel: 'Open chat',
        chatId: 'user-sam1',
      ),
    );
    final isOn = notifications.isEnabled.value;
    if (isShown && isOn) {
      AppNotices.info('show() succeeded. Look in the notification shade.');
    } else if (isShown) {
      AppNotices.error('show() ran but notifications are off for this app.');
    } else {
      AppNotices.error('show() failed. See the notifyflow: log lines.');
    }
  }
}
