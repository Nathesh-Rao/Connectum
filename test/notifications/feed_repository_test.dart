import 'package:connectum/data/e2e/e2e_models.dart';
import 'package:connectum/data/repositories/feed_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/notifications/models/feed_item.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';

Map<String, dynamic> _item(
  String id, {
  int ts = 100,
  bool read = false,
  String priority = 'medium',
  int count = 1,
  bool resolved = false,
  String message = 'hello',
}) => {
  'id': id,
  'ts': ts,
  'read': read,
  'priority': priority,
  'count': count,
  'resolved': resolved,
  'title': 'T$id',
  'message': message,
};

Map<String, dynamic> _counts({int unread = 0, int total = 0}) => {
  'high': 0,
  'medium': total,
  'low': 0,
  'resolved': 0,
  'unread': unread,
  'total': total,
};

Map<String, dynamic> _event(String name, Map<String, dynamic> data) => {
  'type': 'sd_event',
  'event': name,
  'data': data,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late FakeStore store;
  late FakeE2e e2e;
  late FeedRepository feed;

  setUp(() {
    socket = FakeSocket()..goOnline();
    store = FakeStore();
    e2e = FakeE2e();
    feed = FeedRepository(socket, store, e2e)..onInit();
    socket.answers['feed.summary'] = _counts(unread: 2, total: 3);
    socket.answers['feed.list'] = <String, dynamic>{
      'counts': _counts(unread: 2, total: 3),
      'hasMore': true,
      'notifications': [
        _item('a', ts: 300),
        _item('b', ts: 200, read: true),
        _item('c', ts: 100),
      ],
    };
  });

  tearDown(() => feed.onClose());

  group('re-read after a connect or a resume', () {
    test('summary, then the latest 200 items, replace the list', () async {
      feed.items.add(const FeedItem(id: 'old'));
      await feed.refresh();
      expect(socket.calls.map((c) => c.action), ['feed.summary', 'feed.list']);
      final list = socket.calls.last.args;
      expect(list['priority'], 'all');
      expect(list['limit'], 200);
      expect(list.containsKey('before'), isFalse);
      expect(feed.items.map((i) => i.id), ['a', 'b', 'c']);
      expect(feed.unread.value, 2);
      expect(feed.hasMore('all', false), isTrue);
      expect(feed.isLoading.value, isFalse);
    });

    test('two refreshes at once make one pair of calls', () async {
      await Future.wait([feed.refresh(), feed.refresh()]);
      expect(socket.count('feed.summary'), 1);
      expect(socket.count('feed.list'), 1);
    });

    test('offline: nothing is sent and the spinner stops', () async {
      socket.goOffline();
      await feed.refresh();
      expect(socket.calls, isEmpty);
      expect(feed.isLoading.value, isFalse);
    });

    test(
      'a failed first read is an error; a failed re-read keeps the rows',
      () async {
        socket.answers['feed.list'] = const SocketCallError('timeout');
        await feed.refresh();
        expect(feed.hasError.value, isTrue);
        socket.answers['feed.list'] = <String, dynamic>{
          'counts': _counts(total: 1),
          'notifications': [_item('a')],
        };
        await feed.refresh();
        expect(feed.hasError.value, isFalse);
        socket.answers['feed.list'] = const SocketCallError('timeout');
        await feed.refresh();
        expect(feed.items.map((i) => i.id), ['a']);
        expect(feed.hasError.value, isFalse);
      },
    );

    test('a burst of triggers within 150 ms is one read', () {
      fakeAsync((async) {
        for (var i = 0; i < 5; i++) {
          feed.scheduleRefresh();
          async.elapse(const Duration(milliseconds: 40));
        }
        async.elapse(const Duration(milliseconds: 100));
        expect(socket.calls, isEmpty);
        async.elapse(const Duration(milliseconds: 60));
        async.flushMicrotasks();
        expect(socket.count('feed.summary'), 1);
        expect(socket.count('feed.list'), 1);
      });
    });

    test('app resume schedules a read; pause does not', () {
      fakeAsync((async) {
        feed.didChangeAppLifecycleState(AppLifecycleState.paused);
        async.elapse(const Duration(seconds: 1));
        expect(socket.calls, isEmpty);
        feed.didChangeAppLifecycleState(AppLifecycleState.resumed);
        async.elapse(FeedRepository.burst);
        async.flushMicrotasks();
        expect(socket.count('feed.list'), 1);
      });
    });

    test('another person signing in clears everything', () async {
      await feed.refresh();
      store.switchTo('someone-else');
      expect(feed.items, isEmpty);
      expect(feed.unread.value, 0);
      expect(feed.isLoading.value, isTrue);
      expect(feed.hasMore('all', false), isFalse);
    });
  });

  group('the three live events', () {
    setUp(() async => feed.refresh());

    test(
      'feed_item adds the tile, takes the counts and is announced',
      () async {
        final seen = <FeedItem>[];
        final sub = feed.onItem.listen(seen.add);
        feed.onEvent(
          _event('feed_item', {
            'notification': _item('n', ts: 900),
            'counts': _counts(unread: 3, total: 4),
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(feed.items.first.id, 'n');
        expect(feed.unread.value, 3);
        expect(seen.single.id, 'n');
        await sub.cancel();
      },
    );

    test(
      'coalescing: the same id with a higher count replaces and re-opens',
      () {
        feed.onEvent(
          _event('feed_item', {
            'notification': _item('a', ts: 400, count: 3),
            'counts': _counts(unread: 2, total: 3),
          }),
        );
        expect(feed.items.where((i) => i.id == 'a'), hasLength(1));
        expect(feed.items.first.count, 3);
        expect(feed.items.first.isRead, isFalse);
        expect(feed.items, hasLength(3));
      },
    );

    test('an item that arrives already read clears its banner', () async {
      final gone = <List<String>>[];
      final sub = feed.onGone.listen(gone.add);
      feed.onEvent(
        _event('feed_item', {
          'notification': _item('a', read: true),
          'counts': _counts(),
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(gone.single, ['a']);
      await sub.cancel();
    });

    test('feed_removed drops the tiles and clears their banners', () async {
      final gone = <List<String>>[];
      final sub = feed.onGone.listen(gone.add);
      feed.onEvent(
        _event('feed_removed', {
          'ids': ['a', 'zzz'],
          'counts': _counts(unread: 1, total: 2),
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(feed.items.map((i) => i.id), ['b', 'c']);
      expect(feed.unread.value, 1);
      expect(gone.single, ['a', 'zzz']);
      await sub.cancel();
    });

    test(
      'feed_changed read:true marks read and clears; read:false does not',
      () async {
        final gone = <List<String>>[];
        final sub = feed.onGone.listen(gone.add);
        feed.onEvent(
          _event('feed_changed', {
            'ids': ['a'],
            'read': true,
            'counts': _counts(unread: 1, total: 3),
          }),
        );
        expect(feed.items.firstWhere((i) => i.id == 'a').isRead, isTrue);
        feed.onEvent(
          _event('feed_changed', {
            'ids': ['b'],
            'read': false,
            'counts': _counts(unread: 2, total: 3),
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(feed.items.firstWhere((i) => i.id == 'b').isRead, isFalse);
        expect(gone, [
          ['a'],
        ]);
        expect(feed.unread.value, 2);
        await sub.cancel();
      },
    );

    test('an event without counts triggers a re-read', () {
      fakeAsync((async) {
        feed.onEvent(
          _event('feed_changed', {
            'ids': ['a'],
            'read': true,
          }),
        );
        async.elapse(FeedRepository.burst);
        async.flushMicrotasks();
        expect(socket.count('feed.summary'), 2);
      });
    });

    test('an item with no usable id triggers a re-read, not a crash', () {
      fakeAsync((async) {
        feed.onEvent(
          _event('feed_item', {'notification': <String, dynamic>{}}),
        );
        async.elapse(FeedRepository.burst);
        async.flushMicrotasks();
        expect(socket.count('feed.list'), 2);
      });
    });

    test('events that are not sd_event, or unknown, change nothing', () {
      feed.onEvent({'type': 'chat', 'event': 'feed_item'});
      feed.onEvent(_event('something_new', {}));
      expect(feed.items, hasLength(3));
    });
  });

  group('events that only refresh, and their in-app line', () {
    test('task, ticket, request and broadcast lines', () async {
      final lines = <FeedNotice>[];
      final sub = feed.onNotice.listen(lines.add);
      feed.onEvent(
        _event('task_assigned', {
          'task': {'id': 7},
        }),
      );
      feed.onEvent(_event('task_updated', {}));
      feed.onEvent(
        _event('ticket_assigned', {
          'id': 38,
          'tstruct': 'help_ticket',
          'action': 'Raised',
          'by': 'rhea',
        }),
      );
      feed.onEvent(_event('ticket_assigned', {'id': 39, 'action': 'Send'}));
      feed.onEvent(_event('request_created', {}));
      feed.onEvent(_event('broadcast', {'text': 'x' * 300}));
      feed.onEvent(_event('broadcast', {'text': ''}));
      feed.onEvent(_event('request_resolved', {}));
      feed.onEvent(_event('submission_approved', {}));
      await Future<void>.delayed(Duration.zero);
      expect(lines, hasLength(6));
      expect(lines[0].line, 'You have a new task.');
      expect(lines[0].taskId, 7);
      expect(lines[1].line, 'A task was updated.');
      expect(lines[1].taskId, isNull);
      expect(lines[2].line, 'A ticket was raised to you.');
      expect(lines[2].ticketId, 38);
      expect(lines[2].tstruct, 'help_ticket');
      expect(lines[3].line, 'A ticket is now with you.');
      expect(lines[4].line, 'You have a new request to review.');
      expect(lines[5].line, startsWith('Announcement: '));
      expect(lines[5].line.length, lessThanOrEqualTo(120));
      await sub.cancel();
    });
  });

  group('optimistic changes and rollback', () {
    setUp(() async => feed.refresh());

    test('read: the badge drops at once and the server count wins', () async {
      socket.answers['feed.read'] = <String, dynamic>{
        'counts': _counts(unread: 1, total: 3),
      };
      final done = feed.setRead(['a'], isRead: true);
      expect(feed.unread.value, 1);
      expect(feed.items.firstWhere((i) => i.id == 'a').isRead, isTrue);
      await done;
      expect(socket.calls.last.args, {
        'ids': ['a'],
      });
      expect(feed.unread.value, 1);
    });

    test('unread sends read:false', () async {
      socket.answers['feed.read'] = <String, dynamic>{
        'counts': _counts(unread: 3, total: 3),
      };
      await feed.setRead(['b'], isRead: false);
      expect(socket.calls.last.args, {
        'ids': ['b'],
        'read': false,
      });
    });

    test('an error puts the tile and the count back and is rethrown', () async {
      socket.answers['feed.read'] = const SocketCallError(
        'rate_limited',
        'Too many commands -- slow down and retry.',
      );
      await expectLater(
        feed.setRead(['a'], isRead: true),
        throwsA(
          isA<SocketCallError>().having(
            (e) => e.message,
            'message',
            'Too many commands -- slow down and retry.',
          ),
        ),
      );
      expect(feed.items.firstWhere((i) => i.id == 'a').isRead, isFalse);
      expect(feed.unread.value, 2);
    });

    test('resolve: resolved at once; an error restores the tile', () async {
      socket.answers['feed.resolve'] = const SocketCallError(
        'not_found',
        'No such notification.',
      );
      final done = feed.resolve('a');
      expect(feed.items.firstWhere((i) => i.id == 'a').isResolved, isTrue);
      await expectLater(done, throwsA(isA<SocketCallError>()));
      expect(feed.items.firstWhere((i) => i.id == 'a').isResolved, isFalse);
    });

    test('resolve ok: the item and counts of the answer are taken', () async {
      socket.answers['feed.resolve'] = <String, dynamic>{
        'counts': _counts(unread: 1, total: 3),
        'notification': {
          ..._item('a', ts: 300, read: true, priority: 'resolved'),
          'resolved': true,
          'resolvedTs': 5,
        },
      };
      final gone = <List<String>>[];
      final sub = feed.onGone.listen(gone.add);
      await feed.resolve('a');
      await Future<void>.delayed(Duration.zero);
      expect(feed.items.first.id, 'a');
      expect(feed.items.first.resolvedTs, 5);
      expect(gone.single, ['a']);
      await sub.cancel();
    });

    test('dismiss: removed at once; an error brings it back', () async {
      socket.answers['feed.dismiss'] = const SocketCallError('timeout');
      final done = feed.dismiss('c');
      expect(feed.items.any((i) => i.id == 'c'), isFalse);
      await expectLater(done, throwsA(isA<SocketCallError>()));
      expect(feed.items.any((i) => i.id == 'c'), isTrue);
    });

    test('clear resolved sends feed.clear and keeps open tiles', () async {
      feed.items.assignAll([
        ...feed.items,
        const FeedItem(id: 'r', priority: 'resolved', isResolved: true),
      ]);
      socket.answers['feed.clear'] = <String, dynamic>{
        'cleared': 1,
        'counts': _counts(unread: 2, total: 3),
      };
      await feed.clearResolved();
      expect(socket.count('feed.clear'), 1);
      expect(feed.items.map((i) => i.id), ['a', 'b', 'c']);
    });

    test(
      'resolve all: every open tile resolved at once, sends all:true',
      () async {
        socket.answers['feed.resolve'] = <String, dynamic>{'counts': _counts()};
        final gone = <List<String>>[];
        final sub = feed.onGone.listen(gone.add);
        final done = feed.resolveAll();
        expect(feed.items.every((i) => i.isResolved), isTrue);
        expect(feed.unread.value, 0);
        await done;
        await Future<void>.delayed(Duration.zero);
        expect(socket.calls.last.args, {'all': true});
        expect(gone.single, containsAll(['a', 'b', 'c']));
        await sub.cancel();
      },
    );

    test(
      'resolve all: an error brings every tile and the counts back',
      () async {
        socket.answers['feed.resolve'] = const SocketCallError('busy', 'Busy.');
        final done = feed.resolveAll();
        await expectLater(done, throwsA(isA<SocketCallError>()));
        expect(feed.items.where((i) => i.isResolved), isEmpty);
        expect(feed.unread.value, 2);
      },
    );

    test('mark all read: 0 unread at once, rolled back on an error', () async {
      socket.answers['feed.read'] = const SocketCallError('busy', 'Busy.');
      final done = feed.markAllRead();
      expect(feed.unread.value, 0);
      expect(feed.items.every((i) => i.isRead), isTrue);
      await expectLater(done, throwsA(isA<SocketCallError>()));
      expect(feed.unread.value, 2);
      expect(feed.items.where((i) => !i.isRead), hasLength(2));
    });

    test('offline: not_connected, and the change is rolled back', () async {
      socket.goOffline();
      await expectLater(
        feed.dismiss('a'),
        throwsA(
          isA<SocketCallError>().having((e) => e.code, 'code', 'not_connected'),
        ),
      );
      expect(feed.items.any((i) => i.id == 'a'), isTrue);
    });
  });

  group('paging', () {
    setUp(() async => feed.refresh());

    test('loadMore asks after the oldest tile shown', () async {
      socket.answers['feed.list'] = <String, dynamic>{
        'counts': _counts(total: 5),
        'hasMore': false,
        'notifications': [_item('d', ts: 50), _item('e', ts: 40)],
      };
      await feed.loadMore('all', false);
      final args = socket.calls.last.args;
      expect(args['before'], 100);
      expect(args['beforeId'], 'c');
      expect(args['limit'], FeedRepository.pageSize);
      expect(feed.items.map((i) => i.id), ['a', 'b', 'c', 'd', 'e']);
      expect(feed.hasMore('all', false), isFalse);
    });

    test('no more pages: no call', () async {
      socket.answers['feed.list'] = <String, dynamic>{
        'counts': _counts(total: 3),
        'hasMore': false,
        'notifications': <Object>[],
      };
      await feed.loadMore('all', false);
      final before = socket.count('feed.list');
      await feed.loadMore('all', false);
      expect(socket.count('feed.list'), before);
    });

    test('a filter is read once; unreadOnly is sent as asked', () async {
      await feed.ensureFilter('high', true);
      await feed.ensureFilter('high', true);
      final reads = socket.calls.where((c) => c.action == 'feed.list').toList();
      expect(reads, hasLength(2));
      expect(reads.last.args['priority'], 'high');
      expect(reads.last.args['unreadOnly'], isTrue);
    });
  });

  group('text of an end-to-end item', () {
    FeedItem e2eItem() => const FeedItem(
      id: 'e',
      isE2e: true,
      chatId: 'user-ana',
      message: 'e2e1:abc',
      ts: 1,
    );

    test('a plain item is its message and never touches the keys', () async {
      expect(
        await feed.readableText(const FeedItem(id: 'p', message: 'hi')),
        'hi',
      );
      expect(e2e.opened, 0);
    });

    test('opened on the device, once', () async {
      e2e.reading = const E2eReading.ok('secret');
      expect(await feed.readableText(e2eItem()), 'secret');
      expect(await feed.readableText(e2eItem()), 'secret');
      expect(e2e.opened, 1);
    });

    test(
      'cannot open or pending: null (the tile says Encrypted message)',
      () async {
        e2e.reading = const E2eReading.cannot('no_key');
        expect(await feed.readableText(e2eItem()), isNull);
        e2e.reading = const E2eReading.pending();
        expect(await feed.readableText(e2eItem()), isNull);
      },
    );

    test('no chat, or not an envelope: null without trying', () async {
      expect(
        await feed.readableText(
          const FeedItem(id: 'x', isE2e: true, message: 'e2e1:abc'),
        ),
        isNull,
      );
      expect(
        await feed.readableText(
          const FeedItem(
            id: 'y',
            isE2e: true,
            chatId: 'user-a',
            message: 'plain',
          ),
        ),
        isNull,
      );
      expect(e2e.opened, 0);
    });

    test('the cache goes with the session', () async {
      e2e.reading = const E2eReading.ok('secret');
      await feed.readableText(e2eItem());
      store.switchTo('other');
      await feed.readableText(e2eItem());
      expect(e2e.opened, 2);
    });
  });
}
