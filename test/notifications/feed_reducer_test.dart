import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:connectum/features/notifications/models/feed_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

FeedItem item(
  String id, {
  int ts = 1,
  bool read = false,
  String priority = 'medium',
  bool resolved = false,
  int count = 1,
}) => FeedItem(
  id: id,
  ts: ts,
  isRead: read,
  priority: priority,
  isResolved: resolved,
  count: count,
);

void main() {
  test('feed_item adds at the top', () {
    final out = FeedReducer.applyItem([item('a'), item('b')], item('c'));
    expect(out.map((i) => i.id), ['c', 'a', 'b']);
  });

  test('feed_item replaces by id and moves to the top', () {
    final out = FeedReducer.applyItem([
      item('a'),
      item('b'),
    ], item('b', count: 3));
    expect(out.map((i) => i.id), ['b', 'a']);
    expect(out.first.count, 3);
  });

  test('feed_removed drops the ids', () {
    final out = FeedReducer.applyRemoved(
      [item('a'), item('b'), item('c')],
      ['a', 'c', 'zzz'],
    );
    expect(out.map((i) => i.id), ['b']);
  });

  test('feed_changed sets the read flag of the ids only', () {
    final list = [item('a'), item('b', read: true)];
    final read = FeedReducer.applyChanged(list, ['a'], isRead: true);
    expect(read.map((i) => i.isRead), [true, true]);
    final unread = FeedReducer.applyChanged(read, ['b'], isRead: false);
    expect(unread.map((i) => i.isRead), [true, false]);
    expect(list.first.isRead, isFalse, reason: 'the input is not changed');
  });

  test('the list never holds more than 300', () {
    var list = <FeedItem>[];
    for (var i = 0; i < 320; i++) {
      list = FeedReducer.applyItem(list, item('i$i', ts: i));
    }
    expect(list.length, feedCap);
    expect(list.first.id, 'i319');
    expect(list.last.id, 'i20');
    final merged = FeedReducer.merge([], [
      for (var i = 0; i < 350; i++) item('m$i', ts: i),
    ]);
    expect(merged.length, feedCap);
    expect(merged.first.id, 'm349');
  });

  test('a page merges by id, newest first', () {
    final out = FeedReducer.merge(
      [item('a', ts: 5), item('b', ts: 3)],
      [item('b', ts: 3, read: true), item('c', ts: 4)],
    );
    expect(out.map((i) => i.id), ['a', 'c', 'b']);
    expect(out.last.isRead, isTrue);
  });

  test('a (re)connect read replaces the list', () {
    final out = FeedReducer.replace([
      item('c', ts: 3, read: true),
      item('a', ts: 5),
    ]);
    expect(out.map((i) => i.id), ['a', 'c']);
    expect(out.last.isRead, isTrue);
  });

  test('a read drops what is gone and takes the new state of the rest', () {
    final local = [item('a', ts: 5), item('b', ts: 4), item('old', ts: 1)];
    final fetched = [item('a', ts: 5, read: true), item('b', ts: 4)];
    final out = FeedReducer.replace(fetched);
    expect(out.map((i) => i.id), ['a', 'b']);
    expect(out.first.isRead, isTrue);
    expect(local.length, 3, reason: 'the input is not changed');
  });

  test('a read of 200 items keeps all of them', () {
    final out = FeedReducer.replace([
      for (var i = 0; i < 200; i++) item('i$i', ts: i),
    ]);
    expect(out.length, 200);
    expect(out.first.id, 'i199');
  });

  test('an empty read empties the list', () {
    expect(FeedReducer.replace(const []), isEmpty);
  });

  test('items of a muted conversation are left out of a filter', () {
    final list = [
      FeedItem(id: 'dm', chatId: 'user-sam'),
      FeedItem(id: 'grp', chatId: 'room-sales'),
      FeedItem(id: 'task'),
    ];
    final out = FeedReducer.filter(
      list,
      priority: 'all',
      isUnreadOnly: false,
      mutedConversations: {'dm:sam'},
    );
    expect(out.map((i) => i.id), ['grp', 'task']);
  });

  test('filters', () {
    final list = [
      item('h', priority: 'high'),
      item('m', priority: 'medium', read: true),
      item('r', priority: 'resolved', resolved: true),
    ];
    List<String> ids(String p, bool u) => FeedReducer.filter(
      list,
      priority: p,
      isUnreadOnly: u,
    ).map((i) => i.id).toList();
    expect(ids('all', false), ['h', 'm']);
    expect(ids('all', true), ['h']);
    expect(ids('resolved', false), ['r']);
    expect(ids('medium', true), isEmpty);
  });
}
