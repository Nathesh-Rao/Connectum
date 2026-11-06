import 'package:connectum/features/notifications/feed_highlight.dart';
import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

List<(String, bool)> _runs(String text, FeedItem item) {
  const base = TextStyle();
  return [
    for (final s in FeedHighlight.spans(text, item, base: base))
      if (s is TextSpan) (s.text!, s.style != null),
  ];
}

void main() {
  test('the sender, the tags and quoted names are emphasised', () {
    const item = FeedItem(
      id: 'a',
      category: 'messages',
      title: 'Ana',
      from: 'ana',
      actionType: 'open_message',
      chatId: 'room-team',
    );
    expect(_runs('Ana: ping @sam.w about "Q3 plan" please', item), [
      ('Ana', true),
      (': ping ', false),
      ('@sam.w', true),
      (' about ', false),
      ('"Q3 plan"', true),
      (' please', false),
    ]);
  });

  test('the device label of ref is emphasised', () {
    const item = FeedItem(
      id: 'd',
      category: 'security',
      title: 'New sign-in',
      ref: {'deviceLabel': 'moto g32'},
    );
    expect(FeedHighlight.deviceLabel(item), 'moto g32');
    expect(_runs('Signed in on moto g32 just now', item), [
      ('Signed in on ', false),
      ('moto g32', true),
      (' just now', false),
    ]);
  });

  test('plain text stays one plain run', () {
    expect(_runs('Nothing special here', const FeedItem(id: 'p')), [
      ('Nothing special here', false),
    ]);
  });
}
