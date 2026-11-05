import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a full message item', () {
    final item = FeedItem.tryParse({
      'id': 'a1',
      'priority': 'high',
      'category': 'messages',
      'title': 'Sam',
      'message': 'hi',
      'ts': 1790000000000,
      'icon': 'chat',
      'read': false,
      'resolved': false,
      'resolvedTs': null,
      'actionType': 'open_chat',
      'actionLabel': 'Open chat',
      'chatId': 'user-sam1',
      'count': 3,
      'from': 'sam1',
      'chat': {'scope': 'dm', 'with': 'sam1'},
      'ref': {'messageId': 42, 'deviceId': 'd1'},
    })!;
    expect(item.id, 'a1');
    expect(item.isHigh, isTrue);
    expect(item.count, 3);
    expect(item.messageId, '42');
    expect(item.deviceId, 'd1');
    expect(item.conversationId, 'dm:sam1');
    expect(item.extra, isEmpty);
  });

  test('the real server item has no action fields', () {
    final item = FeedItem.tryParse({
      'category': 'reminders',
      'count': 1,
      'icon': 'alarm',
      'id': 'K',
      'message': 'Call the lab',
      'priority': 'medium',
      'read': false,
      'ref': {'cardId': 'c'},
      'resolved': false,
      'resolvedTs': null,
      'severity': 'medium',
      'title': 'Reminder',
      'ts': 1793166706292,
    })!;
    expect(item.actionType, isNull);
    expect(item.chatId, isNull);
    expect(item.conversationId, isNull);
    expect(item.extra, {'severity': 'medium'});
  });

  test('missing fields give defaults, a missing id gives null', () {
    final item = FeedItem.tryParse({'id': 'x'})!;
    expect(item.title, '');
    expect(item.count, 1);
    expect(item.isRead, isFalse);
    expect(item.ref, isEmpty);
    expect(item.priority, 'low');
    expect(FeedItem.tryParse({'title': 'no id'}), isNull);
    expect(FeedItem.tryParse('nope'), isNull);
    expect(FeedItem.tryParse(null), isNull);
  });

  test('a resolved item without a priority is resolved', () {
    expect(
      FeedItem.tryParse({'id': 'x', 'resolved': true})!.priority,
      'resolved',
    );
  });

  test('unknown fields are kept', () {
    final item = FeedItem.tryParse({'id': 'x', 'newThing': 7})!;
    expect(item.extra['newThing'], 7);
  });

  test('a plain message is clipped to 200 characters', () {
    final item = FeedItem.tryParse({'id': 'x', 'message': 'a' * 500})!;
    expect(item.message.length, feedMessageMax);
  });

  test('an e2e item keeps the whole envelope', () {
    final envelope = 'e2e1:${'A' * 600}';
    final item = FeedItem.tryParse({
      'id': 'x',
      'e2e': true,
      'message': envelope,
      'chatId': 'room-team',
    })!;
    expect(item.isE2e, isTrue);
    expect(item.message, envelope);
    expect(item.conversationId, 'group:team');
  });

  test('API message fields', () {
    final item = FeedItem.tryParse({
      'id': 'x',
      'category': 'api',
      'outcome': 'error',
      'source': 'billing',
      'httpStatus': '500',
      'data': {'k': 1},
      'via': 'api',
    })!;
    expect(item.outcome, 'error');
    expect(item.source, 'billing');
    expect(item.httpStatus, 500);
    expect(item.data, {'k': 1});
    expect(item.via, 'api');
  });

  test('counts', () {
    final c = FeedCounts.tryParse({
      'high': 1,
      'medium': '2',
      'unread': 3,
      'total': 9,
    })!;
    expect((c.high, c.medium, c.low, c.unread, c.total), (1, 2, 0, 3, 9));
    expect(c.forPriority('medium'), 2);
    expect(FeedCounts.tryParse(null), isNull);
  });
}
