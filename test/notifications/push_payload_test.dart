import 'package:connectum/data/notifications/push/push_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a map of strings, as a push provider sends it', () {
    final p = PushPayload.tryParse({
      'itemId': 'a1',
      'actionType': 'open_message',
      'chatId': 'user-sam1',
      'messageId': '12',
      'count': '4',
    })!;
    expect(p.itemId, 'a1');
    expect(p.actionType, 'open_message');
    expect(p.chatId, 'user-sam1');
    expect(p.messageId, '12');
    expect(p.count, 4);
  });

  test('a JSON string, as a local notification carries it', () {
    final p = PushPayload.tryParse(
      '{"itemId":"a","actionType":"approvals","ref":{"messageId":9}}',
    )!;
    expect(p.itemId, 'a');
    expect(p.messageId, '9');
    expect(p.count, 1);
  });

  test('missing and empty fields are null', () {
    final p = PushPayload.tryParse({'itemId': 'a', 'chatId': ''})!;
    expect(p.chatId, isNull);
    expect(p.actionType, isNull);
  });

  test('nothing to route by gives null', () {
    expect(PushPayload.tryParse(null), isNull);
    expect(PushPayload.tryParse(''), isNull);
    expect(PushPayload.tryParse('not json'), isNull);
    expect(PushPayload.tryParse('[1]'), isNull);
    expect(PushPayload.tryParse({'other': 'x'}), isNull);
  });

  test('toJson holds only the small routing fields and round-trips', () {
    const p = PushPayload(
      itemId: 'a',
      actionType: 'open_chat',
      chatId: 'room-g',
      count: 3,
    );
    final back = PushPayload.tryParse(p.toJson())!;
    expect(back.itemId, 'a');
    expect(back.chatId, 'room-g');
    expect(back.count, 3);
    expect(p.toJson().contains('message"'), isFalse);
  });
}
