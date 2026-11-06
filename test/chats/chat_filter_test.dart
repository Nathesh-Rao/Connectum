import 'package:connectum/data/models/chat_thread.dart';
import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/features/chats/models/chat_filter.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _c(
  String id, {
  String? title,
  int ts = 1,
  int unread = 0,
  bool pinned = false,
  bool muted = false,
  bool archived = false,
  bool hidden = false,
  String last = '',
}) => Conversation(
  convId: id,
  kind: id.contains(':') ? id.split(':').first : 'global',
  title: title ?? id,
  lastTs: ts,
  unread: unread,
  isPinned: pinned,
  isMuted: muted,
  isArchived: archived,
  isListHidden: hidden,
  lastText: last,
);

final dm = _c('dm:ana', title: 'ana');
final team = _c('group:sales', title: 'sales');
final general = _c('global', title: 'Global');
final host = _c('host:it', title: 'IT desk');
final record = _c('group:rec-ticket-12', title: 'Ticket #12: printer is down');
final care = _c('group:care-ana.lopez', title: 'Ana Lopez');
final hiddenRecord = _c('group:rec-claim-3', title: 'Claim #3', hidden: true);
final unknown = _c('weird:thing', title: 'weird');

List<String> _ids(ChatFilterKind k, List<Conversation> all, {String q = ''}) =>
    ChatFilter.apply(all, k, query: q).map((c) => c.convId).toList()..sort();

void main() {
  final all = [dm, team, general, host, record, care, hiddenRecord, unknown];

  group('which conversation is a thread', () {
    test('record and care groups are threads', () {
      expect(ChatFilter.isThread(record), isTrue);
      expect(ChatFilter.isThread(care), isTrue);
      expect(ChatFilter.isThread(hiddenRecord), isTrue);
    });
    test('direct, group, general, host and unknown kinds are not', () {
      for (final c in [dm, team, general, host, unknown]) {
        expect(ChatFilter.isThread(c), isFalse, reason: c.convId);
      }
    });
    test('a direct chat with a person called care-x is not a thread', () {
      expect(ChatFilter.isThread(_c('dm:care-ana')), isFalse);
    });
    test('names that only look alike are not threads', () {
      expect(ChatThread.isThreadName('rec-ticket'), isFalse);
      expect(ChatThread.isThreadName('rec-ticket-x'), isFalse);
      expect(ChatThread.isThreadName('care-'), isFalse);
      expect(ChatThread.isThreadName('recruiting-2'), isFalse);
      expect(ChatThread.isThreadName('rec-ticket-12'), isTrue);
    });
  });

  group('each chip', () {
    test('All lists everything except what the form hides', () {
      expect(
        _ids(ChatFilterKind.all, all),
        [
          'dm:ana',
          'group:care-ana.lopez',
          'group:rec-ticket-12',
          'group:sales',
          'host:it',
          'weird:thing',
        ]..sort(),
      );
    });
    test('Direct & Teams is everything but hosts and the global room', () {
      expect(
        _ids(ChatFilterKind.direct, all),
        [
          'dm:ana',
          'group:care-ana.lopez',
          'group:rec-ticket-12',
          'group:sales',
          'weird:thing',
        ]..sort(),
      );
    });
    test('Threads lists the threads, hidden ones included', () {
      expect(_ids(ChatFilterKind.threads, all), [
        'group:care-ana.lopez',
        'group:rec-claim-3',
        'group:rec-ticket-12',
      ]);
    });
    test('a hidden record thread is only under Threads', () {
      expect(_ids(ChatFilterKind.all, [hiddenRecord]), isEmpty);
      expect(_ids(ChatFilterKind.direct, [hiddenRecord]), isEmpty);
      expect(_ids(ChatFilterKind.threads, [hiddenRecord]), hasLength(1));
    });
    test('the General Broadcast room is in no chip, as on the web', () {
      expect(ChatFilter.showGeneralBroadcast, isFalse);
      for (final k in ChatFilterKind.values) {
        expect(_ids(k, [general, _c('global', ts: 0)]), isEmpty);
      }
      expect(ChatFilter.isListed(general), isFalse);
    });
    test('an archived conversation is in no chip', () {
      final gone = _c('group:rec-ticket-9', archived: true);
      for (final k in ChatFilterKind.values) {
        expect(_ids(k, [gone, _c('dm:a', archived: true)]), isEmpty);
      }
    });
  });

  group('search with a chip', () {
    test('matches the title and the last text, any case', () {
      final list = [
        _c('dm:bob', title: 'Bob', last: 'printer jammed'),
        record,
        team,
      ];
      expect(_ids(ChatFilterKind.all, list, q: 'PRINTER'), [
        'dm:bob',
        'group:rec-ticket-12',
      ]);
    });
    test('is combined with the chip', () {
      final list = [_c('dm:bob', title: 'Bob', last: 'printer'), record];
      expect(_ids(ChatFilterKind.threads, list, q: 'printer'), [
        'group:rec-ticket-12',
      ]);
      expect(_ids(ChatFilterKind.threads, list, q: 'bob'), isEmpty);
    });
    test('a blank query lists everything of the chip', () {
      expect(_ids(ChatFilterKind.direct, all, q: '  '), hasLength(5));
    });
  });

  group('order and counts', () {
    test('pinned first, then newest', () {
      final list = [
        _c('dm:old', ts: 1),
        _c('dm:new', ts: 9),
        _c('dm:pin', ts: 2, pinned: true),
      ];
      expect(ChatFilter.apply(list, ChatFilterKind.all).map((c) => c.convId), [
        'dm:pin',
        'dm:new',
        'dm:old',
      ]);
    });
    test('a muted conversation stays in its place', () {
      final list = [_c('dm:a', ts: 1), _c('dm:m', ts: 5, muted: true)];
      expect(ChatFilter.apply(list, ChatFilterKind.all).map((c) => c.convId), [
        'dm:m',
        'dm:a',
      ]);
    });
    test('Threads exist while any thread does, an archived one too', () {
      expect(ChatFilter.hasThreads([dm, team]), isFalse);
      expect(
        ChatFilter.hasThreads([dm, _c('group:rec-a-1', archived: true)]),
        isTrue,
      );
    });
    test('the Threads count sums unread, muted and archived included', () {
      final list = [
        _c('group:rec-a-1', unread: 2),
        _c('group:care-bo', unread: 3, muted: true),
        _c('group:rec-b-2', unread: 4, archived: true),
        _c('dm:x', unread: 50),
      ];
      expect(ChatFilter.threadUnread(list), 9);
    });
  });

  group('titles', () {
    test('a thread name is tidied until the server gives a title', () {
      expect(ChatThread.fallbackTitle('rec-ticket-12'), 'Ticket #12');
      expect(
        ChatThread.fallbackTitle('rec-purchase-order-7'),
        'Purchase Order #7',
      );
      expect(ChatThread.fallbackTitle('care-ana.lopez'), 'Ana Lopez');
      expect(ChatThread.fallbackTitle('sales'), 'sales');
    });
    test('the stored server title wins, hidden is read from the row', () {
      final c = Conversation.fromRow({
        'conv_id': 'group:rec-ticket-12',
        'kind': 'group',
        'title': 'rec-ticket-12',
        'thread_title': 'Ticket #12: printer is down',
        'is_list_hidden': 1,
      });
      expect(c.title, 'Ticket #12: printer is down');
      expect(c.isListHidden, isTrue);
      final bare = Conversation.fromRow({
        'conv_id': 'group:rec-ticket-12',
        'kind': 'group',
        'title': 'rec-ticket-12',
      });
      expect(bare.title, 'Ticket #12');
      expect(bare.isListHidden, isFalse);
    });
  });
}
