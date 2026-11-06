import 'package:connectum/data/notifications/local_notification_rules.dart';
import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:flutter_test/flutter_test.dart';

FeedItem item({
  String id = 'x',
  String priority = 'medium',
  String? from,
  String? chatId,
  String? category,
  String? actionType,
  bool e2e = false,
  Map<String, dynamic> chat = const {},
}) => FeedItem(
  id: id,
  priority: priority,
  from: from,
  chatId: chatId,
  category: category,
  actionType: actionType,
  isE2e: e2e,
  chat: chat.isEmpty ? null : chat,
);

NotificationShow decide(
  FeedItem i, {
  Set<String> muted = const {},
  String? open,
  String? me = 'me',
}) => LocalNotificationRules.decide(
  i,
  myUser: me,
  mutedConversations: muted,
  openConversationId: open,
);

void main() {
  group(
    'the kinds of item in the catalogue (what the phone does in the background)',
    () {
      test(
        'direct message (medium) and urgent direct message (high): system',
        () {
          expect(
            decide(item(chatId: 'user-ana', from: 'ana')),
            NotificationShow.system,
          );
          expect(
            decide(item(priority: 'high', chatId: 'user-ana', from: 'ana')),
            NotificationShow.system,
          );
        },
      );

      test(
        'group message is low: a system notification while the switch is on',
        () {
          final g = item(
            priority: 'low',
            actionType: 'open_chat',
            chatId: 'room-team',
            from: 'ana',
          );
          expect(decide(g), NotificationShow.system);
        },
      );

      test(
        'mention (medium) in a normal group notifies; in a muted group it is quiet',
        () {
          final m = item(
            chatId: 'room-team',
            actionType: 'open_message',
            from: 'ana',
          );
          expect(decide(m), NotificationShow.system);
          expect(decide(m, muted: {'group:team'}), NotificationShow.none);
        },
      );

      test(
        'approval, ticket, task, outcome, submission, announcement: system when medium or high',
        () {
          for (final p in ['medium', 'high']) {
            expect(
              decide(item(priority: p, actionType: 'approvals')),
              NotificationShow.system,
            );
            expect(
              decide(item(priority: p, actionType: 'tickets')),
              NotificationShow.system,
            );
            expect(
              decide(item(priority: p, category: 'system')),
              NotificationShow.system,
            );
          }
        },
      );

      test('an API message with severity low stays quiet', () {
        expect(
          decide(item(priority: 'low', category: 'api')),
          NotificationShow.none,
        );
      });
    },
  );

  group('who the item is from and which chat it names', () {
    test('my own action is silent whatever the case of my name', () {
      expect(decide(item(from: 'ME')), NotificationShow.none);
      expect(decide(item(from: 'me'), me: 'Me'), NotificationShow.none);
    });

    test('with no signed-in user the own-action rule cannot apply', () {
      expect(decide(item(from: 'me'), me: null), NotificationShow.system);
    });

    test('the chat is found from chatId or from the chat object', () {
      expect(
        decide(item(chatId: 'room-team'), muted: {'group:team'}),
        NotificationShow.none,
      );
      expect(
        decide(item(chat: {'scope': 'dm', 'with': 'ana'}), muted: {'dm:ana'}),
        NotificationShow.none,
      );
      expect(
        decide(item(chatId: 'user-ana'), open: 'dm:ana'),
        NotificationShow.none,
      );
    });

    test('an e2e item is judged only by its metadata, never its text', () {
      final e = item(e2e: true, chatId: 'user-ana', from: 'ana');
      expect(decide(e), NotificationShow.system);
      expect(decide(e, muted: {'dm:ana'}), NotificationShow.none);
    });

    test('a coalesced item that became unread again can notify again', () {
      final again = item(id: 'dm:ana', chatId: 'user-ana', from: 'ana');
      expect(decide(again), NotificationShow.system);
      expect(
        LocalNotificationRules.notificationId('dm:ana'),
        LocalNotificationRules.notificationId('dm:ana'),
      );
    });
  });

  group('channels by catalogue type', () {
    test('every type lands in one of the five channels', () {
      const ok = {'messages', 'approvals', 'tasks', 'system', 'security'};
      for (final i in [
        item(category: 'messages', actionType: 'open_chat'),
        item(actionType: 'open_message'),
        item(category: 'approvals', actionType: 'approvals'),
        item(actionType: 'tickets'),
        item(actionType: 'submissions'),
        item(category: 'security'),
        item(category: 'api'),
        item(category: 'system'),
        item(),
      ]) {
        expect(ok, contains(LocalNotificationRules.channelOf(i)));
      }
    });

    test('a to-do (system, no action) is in the system channel, not tasks', () {
      expect(
        LocalNotificationRules.channelOf(item(category: 'system')),
        'system',
      );
    });
  });

  group('words of a notification', () {
    test('clip keeps short text and ends a long one with an ellipsis', () {
      expect(FeedItem.clip('abc', 100), 'abc');
      final long = FeedItem.clip('a' * 300, LocalNotificationRules.bodyMax);
      expect(long.length, LocalNotificationRules.bodyMax);
      expect(long.endsWith('…'), isTrue);
    });
  });
}
