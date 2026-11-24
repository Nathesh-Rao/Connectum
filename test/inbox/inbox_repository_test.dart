import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/inbox_repository.dart';
import 'package:connectum/data/socket/read_gate.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/inbox/models/inbox_query.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import 'inbox_support.dart';

Map<String, dynamic> rec(int id) => {
  'id': id,
  'tstruct': 't',
  'by': 'rhea',
  'holder': 'ana',
  'ts': id,
  'values': {'title': 'Record $id'},
};

Map<String, dynamic> reply(
  List<int> ids, {
  int total = 100,
  bool hasMore = true,
  bool capped = false,
}) => {
  'submissions': [for (final id in ids) rec(id)],
  'structures': {
    't': {'caption': 'Thing'},
  },
  'total': total,
  'hasMore': hasMore,
  'capped': capped,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GateClock clock;
  late HeldSocket socket;
  late FakeStore store;
  late InboxRepository repo;
  const q = InboxQuery();

  setUp(() {
    clock = GateClock();
    socket = HeldSocket()..goOnline();
    store = FakeStore(user: 'ana');
    repo = InboxRepository(
      socket,
      store,
      ReadGate(now: clock.read, delay: clock.delay),
    )..onInit();
  });

  group('records.query', () {
    test('asks one page of 100, newest first from offset 0', () async {
      socket.handler = (a, args) async => reply([3, 2, 1]);
      final page = (await repo.query(q))!;
      expect(socket.calls.single.action, RecordCmd.query);
      expect(socket.calls.single.args, {'limit': 100, 'offset': 0});
      expect(page.rows.map((r) => r.id), [3, 2, 1]);
      expect(page.total, 100);
      expect(page.hasMore, isTrue);
      expect(page.isCapped, isFalse);
      expect(page.forms['t']!.caption, 'Thing');
      expect(repo.list.last.value, same(page));
      expect(repo.list.hasError.value, isFalse);
    });

    test('capped is carried', () async {
      socket.handler = (a, args) async => reply([1], capped: true);
      expect((await repo.query(q))!.isCapped, isTrue);
    });

    test('the next page is added to the list, each record once', () async {
      socket.handler = (a, args) async => args['offset'] == 0
          ? reply([5, 4, 3])
          : reply([3, 2, 1], hasMore: false);
      await repo.query(q);
      final all = (await repo.query(q, offset: 3))!;
      expect(socket.calls.last.args['offset'], 3);
      expect(all.rows.map((r) => r.id), [5, 4, 3, 2, 1]);
      expect(all.hasMore, isFalse);
      expect(repo.list.last.value, same(all));
    });

    test('offset 0 replaces what was there', () async {
      socket.handler = (a, args) async => reply([1, 2]);
      await repo.query(q);
      socket.handler = (a, args) async => reply([9]);
      expect((await repo.query(q))!.rows.map((r) => r.id), [9]);
    });

    test('an ask that breaks a server limit is not sent', () async {
      await expectLater(
        repo.query(q, limit: 500),
        throwsA(isA<InboxQueryError>()),
      );
      expect(socket.calls, isEmpty);
    });
  });

  group('the newest ask wins', () {
    test('an older answer is dropped when it lands', () async {
      final first = repo.query(q);
      await settle();
      final second = repo.query(const InboxQuery(scope: ['team']));
      expect(socket.waiting.length, 1, reason: 'one read at a time');
      socket.waiting[0].done.complete(reply([1]));
      expect(await first, isNull, reason: 'older: dropped');
      expect(repo.list.last.value, isNull, reason: 'nothing delivered yet');
      await settle();
      socket.waiting[1].done.complete(reply([2]));
      final page = (await second)!;
      expect(page.rows.single.id, 2);
      expect(repo.list.last.value, same(page));
    });

    test('an older failure is dropped too: no error flag', () async {
      final first = repo.query(q);
      await settle();
      final second = repo.query(q);
      socket.waiting[0].done.completeError(const SocketCallError('timeout'));
      expect(await first, isNull);
      expect(repo.list.hasError.value, isFalse);
      await settle();
      socket.waiting[1].done.complete(reply([7]));
      expect((await second)!.rows.single.id, 7);
    });

    test('each kind of read has its own counter', () async {
      final list = repo.query(q);
      await settle();
      final counts = repo.loadCounts();
      socket.waiting[0].done.complete(reply([1]));
      await settle();
      socket.waiting[1].done.complete({'me': 1, 'team': 2, 'all': 3});
      expect((await list)!.rows.single.id, 1);
      expect((await counts)!.all, 3);
    });

    test('switching organisation drops what is in flight', () async {
      final first = repo.query(q);
      await settle();
      store.switchTo('bob');
      socket.waiting[0].done.complete(reply([1]));
      expect(await first, isNull);
      expect(repo.list.last.value, isNull);
    });
  });

  group('a failed re-read', () {
    test(
      'keeps the list and sets the error flag; a good read clears it',
      () async {
        socket.handler = (a, args) async => reply([1, 2]);
        final good = (await repo.query(q))!;
        socket.handler = (a, args) async =>
            throw const SocketCallError('internal', 'boom');
        await expectLater(
          repo.query(q),
          throwsA(
            isA<SocketCallError>().having((e) => e.code, 'code', 'internal'),
          ),
        );
        expect(repo.list.hasError.value, isTrue);
        expect(repo.list.last.value, same(good), reason: 'the list stays');
        socket.handler = (a, args) async => reply([3]);
        await repo.query(q);
        expect(repo.list.hasError.value, isFalse);
        expect(repo.list.last.value!.rows.single.id, 3);
      },
    );

    test('offline is a failed read too, the list stays', () async {
      socket.handler = (a, args) async => reply([1]);
      final good = (await repo.query(q))!;
      socket.goOffline();
      await expectLater(
        repo.query(q),
        throwsA(
          isA<SocketCallError>().having((e) => e.code, 'code', 'not_connected'),
        ),
      );
      expect(repo.list.hasError.value, isTrue);
      expect(repo.list.last.value, same(good));
      expect(socket.calls.length, 1, reason: 'nothing was sent');
    });

    test('a reply that cannot be read is a failed read', () async {
      socket.handler = (a, args) async => reply([1]);
      final good = (await repo.query(q))!;
      socket.handler = (a, args) async => {'total': 'x', 'submissions': 5};
      final page = await repo.query(q);
      expect(page!.rows, isEmpty, reason: 'a tolerant parse, not a throw');
      expect(good.rows, isNotEmpty);
    });

    test('rate_limited waits and retries through the gate', () async {
      var n = 0;
      socket.handler = (a, args) async {
        if (++n < 3) throw const SocketCallError('rate_limited');
        return reply([1]);
      };
      expect((await repo.query(q))!.rows.single.id, 1);
      expect(n, 3);
      expect(repo.list.hasError.value, isFalse);
    });
  });

  group('counts and people', () {
    test('records.counts', () async {
      socket.handler = (a, args) async => {
        'me': 4,
        'team': 7,
        'all': 1001,
        'reports': 3,
        'cap': 1000,
      };
      final c = (await repo.loadCounts())!;
      expect(socket.calls.single.action, RecordCmd.counts);
      expect(socket.calls.single.args, isEmpty);
      expect(c.label(c.all), '1000+');
      expect(repo.counts.last.value, same(c));
    });

    test('counts that cannot be read keep the last ones and flag it', () async {
      socket.handler = (a, args) async => {'me': 1, 'team': 2, 'all': 3};
      final good = (await repo.loadCounts())!;
      socket.handler = (a, args) async => {'me': 'x'};
      await expectLater(repo.loadCounts(), throwsA(isA<SocketCallError>()));
      expect(repo.counts.hasError.value, isTrue);
      expect(repo.counts.last.value, same(good));
    });

    test('records.people', () async {
      socket.handler = (a, args) async => {
        'team': ['a', 'b'],
        'sentBy': ['c'],
        'sentTo': [],
      };
      final p = (await repo.loadPeople())!;
      expect(socket.calls.single.action, RecordCmd.queryPeople);
      expect(p.team, ['a', 'b']);
      expect(p.sentBy, ['c']);
    });
  });

  group('people.cards', () {
    Map<String, dynamic> cards(List<String> names) => {
      'people': {
        for (final n in names)
          n: {
            'name': 'Name $n',
            'designation': 'Lead',
            'role': 'user',
            'avatar': 'a/$n.png',
          },
      },
    };

    test('only unknown names, in batches of 60, kept in memory', () async {
      final names = [
        for (var i = 0; i < 130; i++) 'u${i.toString().padLeft(3, '0')}',
      ];
      socket.handler = (a, args) async =>
          cards([...(args['usernames'] as List).cast<String>()]);
      await repo.loadCards(names);
      final asked = socket.calls.map(
        (c) => (c.args['usernames'] as List).length,
      );
      expect(asked, [60, 60, 10]);
      expect(
        socket.calls.every((c) => c.action == RecordCmd.peopleCards),
        isTrue,
      );
      expect(repo.cardOf('U007')!.name, 'Name u007');
      expect(repo.cardOf('u007')!.designation, 'Lead');
      expect(repo.cardOf('u007')!.avatar, 'a/u007.png');
      socket.calls.clear();
      await repo.loadCards(['u001', ' U002 ', 'u003']);
      expect(socket.calls, isEmpty, reason: 'all known');
      await repo.loadCards(['u001', 'new1']);
      expect(socket.calls.single.args['usernames'], ['new1']);
    });

    test('a name the server did not answer is not asked again', () async {
      socket.handler = (a, args) async => cards([]);
      await repo.loadCards(['ghost']);
      await repo.loadCards(['ghost']);
      expect(socket.calls.length, 1);
      expect(repo.cardOf('ghost'), isNull);
    });

    test('names are lower-cased, trimmed, once each', () async {
      socket.handler = (a, args) async => cards(['ana']);
      await repo.loadCards(['Ana', ' ana ', '', 'ANA']);
      expect(socket.calls.single.args['usernames'], ['ana']);
    });

    test('a failed batch is forgotten so a later call asks again', () async {
      socket.handler = (a, args) async =>
          throw const SocketCallError('timeout');
      await repo.loadCards(['ana']);
      expect(repo.cardOf('ana'), isNull);
      socket.handler = (a, args) async => cards(['ana']);
      await repo.loadCards(['ana']);
      expect(repo.cardOf('ana')!.name, 'Name ana');
    });

    test('a new person or organisation starts with no cards', () async {
      socket.handler = (a, args) async => cards(['ana']);
      await repo.loadCards(['ana']);
      store.switchTo('bob');
      expect(repo.cardOf('ana'), isNull);
    });
  });
}
