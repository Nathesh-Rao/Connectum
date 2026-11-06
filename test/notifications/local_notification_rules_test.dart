import 'package:connectum/data/notifications/local_notification_rules.dart';
import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:flutter_test/flutter_test.dart';

FeedItem item({
  String priority = 'medium',
  bool read = false,
  bool resolved = false,
  String? from = 'sam1',
  String? chatId = 'user-sam1',
  bool e2e = false,
  String? category,
  String? actionType,
}) => FeedItem(
  id: 'x',
  priority: priority,
  isRead: read,
  isResolved: resolved,
  from: from,
  chatId: chatId,
  isE2e: e2e,
  category: category,
  actionType: actionType,
);

NotificationShow decide(
  FeedItem i, {
  Set<String> muted = const {},
  String? open,
  bool shouldNotifyGroups = true,
}) => LocalNotificationRules.decide(
  i,
  myUser: 'me',
  mutedConversations: muted,
  openConversationId: open,
  shouldNotifyGroups: shouldNotifyGroups,
);

void main() {
  test('background: a new medium message is a system notification', () {
    expect(decide(item()), NotificationShow.system);
  });

  test('high and medium notify, low does not, in either app state', () {
    expect(decide(item()), NotificationShow.system);
    expect(decide(item(priority: 'high')), NotificationShow.system);
    expect(decide(item(priority: 'low')), NotificationShow.none);
  });

  test('every skip carries its reason', () {
    String why(FeedItem i, {Set<String> muted = const {}, String? open}) =>
        LocalNotificationRules.explain(
          i,
          myUser: 'me',
          mutedConversations: muted,
          openConversationId: open,
        ).reason;
    expect(why(item()), 'shown');
    expect(why(item(read: true)), 'skipped: read or resolved');
    expect(why(item(from: 'me')), 'skipped: own action');
    expect(why(item(), muted: {'dm:sam1'}), 'skipped: muted');
    expect(why(item(), open: 'dm:sam1'), 'skipped: open conversation');
    expect(why(item(priority: 'low')), 'skipped: low severity');
  });

  test('low severity that is not a group message stays silent', () {
    expect(decide(item(priority: 'low')), NotificationShow.none);
    expect(
      decide(item(priority: 'low', category: 'api', chatId: null)),
      NotificationShow.none,
    );
  });

  group('group messages (low) with the setting', () {
    FeedItem group({String chatId = 'room-team', String? from = 'ana'}) => item(
      priority: 'low',
      actionType: 'open_chat',
      chatId: chatId,
      from: from,
    );

    test('on: a background group message is a system notification', () {
      expect(decide(group()), NotificationShow.system);
    });

    test('off: it stays silent, mentions and direct messages still notify', () {
      expect(decide(group(), shouldNotifyGroups: false), NotificationShow.none);
      expect(
        decide(
          item(actionType: 'open_message', chatId: 'room-team'),
          shouldNotifyGroups: false,
        ),
        NotificationShow.system,
      );
      expect(
        decide(item(), shouldNotifyGroups: false),
        NotificationShow.system,
      );
    });

    test('on: muted group, my own message and the open group are silent', () {
      expect(decide(group(), muted: {'group:team'}), NotificationShow.none);
      expect(decide(group(from: 'Me')), NotificationShow.none);
      expect(decide(group(), open: 'group:team'), NotificationShow.none);
    });

    test('a direct chat or a low item with no open_chat is not a group', () {
      expect(
        decide(
          item(priority: 'low', actionType: 'open_chat', chatId: 'user-ana'),
        ),
        NotificationShow.none,
      );
      expect(
        decide(item(priority: 'low', chatId: 'room-team')),
        NotificationShow.none,
      );
    });
  });

  test('read and resolved items are silent', () {
    expect(decide(item(read: true)), NotificationShow.none);
    expect(decide(item(resolved: true)), NotificationShow.none);
  });

  test('my own action is silent', () {
    expect(decide(item(from: 'Me')), NotificationShow.none);
    expect(decide(item(from: null)), NotificationShow.system);
  });

  test('a muted conversation is silent', () {
    expect(decide(item(), muted: {'dm:sam1'}), NotificationShow.none);
    expect(decide(item(), muted: {'dm:other'}), NotificationShow.system);
  });

  test('the open conversation is silent', () {
    expect(decide(item(), open: 'dm:sam1'), NotificationShow.none);
    expect(decide(item(), open: 'dm:other'), NotificationShow.system);
  });

  test('an e2e item follows the same rules', () {
    expect(decide(item(e2e: true)), NotificationShow.system);
    expect(decide(item(e2e: true), muted: {'dm:sam1'}), NotificationShow.none);
  });

  test('an item with no chat is not muted by a chat rule', () {
    expect(
      decide(item(chatId: null), muted: {'dm:sam1'}, open: 'dm:sam1'),
      NotificationShow.system,
    );
  });

  test('channels', () {
    String ch(FeedItem i) => LocalNotificationRules.channelOf(i);
    expect(ch(item(category: 'messages')), 'messages');
    expect(ch(item(category: 'security', chatId: null)), 'security');
    expect(ch(item(category: 'approvals', chatId: null)), 'approvals');
    expect(
      ch(item(actionType: 'tickets', chatId: null, category: 'system')),
      'tasks',
    );
    expect(ch(item(category: 'reminders', chatId: null)), 'system');
  });

  test('the notification id is stable and positive', () {
    final a = LocalNotificationRules.notificationId('abc');
    expect(LocalNotificationRules.notificationId('abc'), a);
    expect(a, isNonNegative);
    expect(a, lessThanOrEqualTo(0x7fffffff));
    expect(LocalNotificationRules.notificationId('abd'), isNot(a));
  });
}
