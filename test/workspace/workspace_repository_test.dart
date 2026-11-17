import 'dart:async';

import 'package:connectum/data/records/paged_read.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/repositories/workspace_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

Map<String, dynamic> _row(
  int id, {
  String by = 'rhea',
  int ts = 100,
  int? editedTs,
  String? status,
}) => {
  'id': id,
  'tstruct': 'help_ticket',
  'by': by,
  'holder': 'ana',
  'ts': ts,
  'editedTs': ?editedTs,
  'status': ?status,
  'values': {'title': 'Row $id', 'stage': 'Open'},
};

const _structures = {
  'help_ticket': {
    'caption': 'Ticket',
    'fields': {'title': 'Title', 'stage': 'Stage'},
    'status': {
      'field': 'stage',
      'statuses': ['Open', 'Done'],
      'final': ['Done'],
    },
  },
};

Map<String, dynamic> _page(
  List<Map<String, dynamic>> rows, {
  bool hasMore = false,
}) => {
  'submissions': rows,
  'structures': _structures,
  'total': rows.length,
  'hasMore': hasMore,
  'next': null,
};

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late FakeStore store;
  late TicketRepository tickets;
  late WorkspaceRepository repo;
  late int ownReads;
  late bool ownOk;
  late List<DateTime> readTimes;

  WorkspaceRepository make({
    Duration debounce = const Duration(milliseconds: 20),
    Duration minGap = Duration.zero,
  }) => WorkspaceRepository(
    socket,
    store,
    tickets,
    syncOwn: () async {
      ownReads++;
      readTimes.add(DateTime.now());
      return ownOk;
    },
    debounce: debounce,
    minGap: minGap,
    pageGap: Duration.zero,
  )..onInit();

  List<int> offsets(String as) => [
    for (final c in socket.calls)
      if (c.action == RecordCmd.mine && c.args['as'] == as)
        (c.args['offset'] as int?) ?? 0,
  ];

  setUp(() {
    socket = FakeSocket()..goOnline();
    store = FakeStore(user: 'ana');
    tickets = TicketRepository(socket, store, FakeConversations())..onInit();
    ownReads = 0;
    ownOk = true;
    readTimes = [];
    socket.answers[RecordCmd.mine] = (_) => _page(const []);
  });

  tearDown(() {
    repo.onClose();
    tickets.onClose();
  });

  group('assembly', () {
    test('involved and with are merged: once per id, never mine, never '
        'waiting, newest first by when they came', () async {
      repo = make();
      socket.answers[RecordCmd.mine] = (a) => a['as'] == 'involved'
          ? _page([
              _row(1, ts: 100, editedTs: 500),
              _row(2, by: 'ana', ts: 900),
              _row(3, ts: 800, status: 'pending'),
            ])
          : _page([_row(1, ts: 100), _row(4, ts: 300), _row(5, ts: 200)]);
      await repo.syncNow();
      expect(repo.received.map((t) => t.id), [1, 4, 5]);
      expect(ownReads, 1);
      expect(repo.isLoaded.value, isTrue);
      expect(repo.hasError.value, isFalse);
      expect(socket.count(RecordCmd.mine), 2);
    });

    test('an empty answer is empty and loaded, not an error', () async {
      repo = make();
      await repo.syncNow();
      expect(repo.received, isEmpty);
      expect(repo.isLoaded.value, isTrue);
      expect(repo.hasError.value, isFalse);
    });

    test('paging continues at offset += rows received while hasMore, '
        'whatever next says (null) and however short a page is', () async {
      repo = make();
      final pages = <int, List<int>>{
        0: [1, 2, 3, 4, 5],
        5: [6, 7, 8],
        8: [9, 10],
      };
      socket.answers[RecordCmd.mine] = (a) {
        if (a['as'] != 'involved') return _page(const []);
        final offset = (a['offset'] as int?) ?? 0;
        return _page([
          for (final i in pages[offset] ?? const <int>[]) _row(i, ts: 1000 - i),
        ], hasMore: offset < 8);
      };
      await repo.syncNow();
      expect(offsets('involved'), [0, 5, 8]);
      expect(repo.received.map((t) => t.id), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });

    test('a page of rows nobody can read still moves the offset', () async {
      repo = make();
      socket.answers[RecordCmd.mine] = (a) {
        if (a['as'] != 'involved') return _page(const []);
        final offset = (a['offset'] as int?) ?? 0;
        return offset == 0
            ? _page([
                {'id': 'x'},
                {'tstruct': 'no id'},
              ], hasMore: true)
            : _page([_row(7)]);
      };
      await repo.syncNow();
      expect(offsets('involved'), [0, 2]);
      expect(repo.received.map((t) => t.id), [7]);
    });
  });

  group('errors are never an empty list', () {
    test('a failed first read is an error, not "nothing"', () async {
      repo = make();
      socket.answers[RecordCmd.mine] = const SocketCallError('timeout');
      await repo.syncNow();
      expect(repo.hasError.value, isTrue);
      expect(repo.isLoaded.value, isFalse);
      expect(repo.received, isEmpty);
    });

    test('a failed later read keeps what was shown and says so', () async {
      repo = make();
      socket.answers[RecordCmd.mine] = (a) =>
          a['as'] == 'with' ? _page([_row(4)]) : _page(const []);
      await repo.syncNow();
      expect(repo.received.map((t) => t.id), [4]);
      socket.answers[RecordCmd.mine] = const SocketCallError('internal');
      await repo.syncNow();
      expect(repo.received.map((t) => t.id), [4]);
      expect(repo.hasError.value, isTrue);
      expect(repo.isLoaded.value, isTrue);
      socket.answers[RecordCmd.mine] = (a) => _page(const []);
      await repo.syncNow();
      expect(repo.hasError.value, isFalse);
      expect(repo.received, isEmpty);
    });

    test('a failed own read is an error too', () async {
      repo = make();
      ownOk = false;
      await repo.syncNow();
      expect(repo.hasError.value, isTrue);
    });

    test('a page that fails half way keeps the old list', () async {
      repo = make();
      socket.answers[RecordCmd.mine] = (a) => a['as'] == 'involved'
          ? _page([_row(1)], hasMore: true)
          : _page(const []);
      socket.answers[RecordCmd.mine] = (a) {
        if (a['as'] != 'involved') return _page(const []);
        if (((a['offset'] as int?) ?? 0) == 0) {
          return _page([_row(1)], hasMore: true);
        }
        throw const SocketCallError('timeout');
      };
      await repo.syncNow();
      expect(repo.hasError.value, isTrue);
      expect(repo.received, isEmpty);
    });
  });

  group('refresh', () {
    test('submissions_changed, ticket_assigned and feed_item read again; '
        'a burst is one read', () async {
      repo = make();
      for (var i = 0; i < 5; i++) {
        repo.onEvent({'type': 'sd_event', 'event': RecordEvents.changed});
        repo.onEvent({'type': 'sd_event', 'event': RecordEvents.assigned});
        repo.onEvent({'type': 'sd_event', 'event': RecordEvents.feedItem});
      }
      await _wait(150);
      expect(repo.syncs, 1);
      expect(ownReads, 1);
      expect(socket.count(RecordCmd.mine), 2);
    });

    test('other events do not read', () async {
      repo = make();
      repo.onEvent({'type': 'sd_event', 'event': 'typing'});
      repo.onEvent({'type': 'message'});
      await _wait(100);
      expect(repo.syncs, 0);
    });

    test('an event during a read asks for one more read, not a loop', () async {
      repo = make();
      final gate = Completer<void>();
      socket.held[RecordCmd.mine] = gate.future;
      final first = repo.syncNow();
      await _wait(10);
      repo.onEvent({'type': 'sd_event', 'event': RecordEvents.changed});
      repo.onEvent({'type': 'sd_event', 'event': RecordEvents.changed});
      gate.complete();
      await first;
      await _wait(150);
      expect(repo.syncs, 2);
    });

    test('reads are at least minGap apart however many events come', () async {
      repo = make(minGap: const Duration(milliseconds: 400));
      repo.request(now: true);
      await _wait(60);
      expect(repo.syncs, 1);
      for (var i = 0; i < 20; i++) {
        repo.onEvent({'type': 'sd_event', 'event': RecordEvents.changed});
        await _wait(5);
      }
      await _wait(100);
      expect(repo.syncs, 1, reason: 'the gap has not passed');
      await _wait(400);
      expect(repo.syncs, 2);
      expect(
        readTimes[1].difference(readTimes[0]),
        greaterThanOrEqualTo(const Duration(milliseconds: 390)),
      );
    });

    test('a refresh is at most three commands, and twenty events cost the '
        'same as one', () async {
      repo = make();
      for (var i = 0; i < 20; i++) {
        repo.onEvent({'type': 'sd_event', 'event': RecordEvents.changed});
      }
      await _wait(150);
      // own list + involved + with, one page each.
      expect(ownReads + socket.count(RecordCmd.mine), lessThanOrEqualTo(3));
    });

    test('a full read of 3 lists of 10 pages stays under 30 commands per '
        'burst: the page limit is explicit', () async {
      repo = make();
      socket.answers[RecordCmd.mine] = (a) => _page([
        _row(((a['offset'] as int?) ?? 0) + 1 + (a['as'] == 'with' ? 5000 : 0)),
      ], hasMore: true);
      await repo.syncNow();
      expect(socket.count(RecordCmd.mine), 2 * WorkspaceRepository.maxPages);
      expect(repo.received.length, 2 * WorkspaceRepository.maxPages);
    });
  });

  group('organisation', () {
    test(
      'switching organisation clears the list and reads the new one',
      () async {
        repo = make();
        socket.answers[RecordCmd.mine] = (a) =>
            a['as'] == 'with' ? _page([_row(4)]) : _page(const []);
        await repo.syncNow();
        expect(repo.received.map((t) => t.id), [4]);
        socket.answers[RecordCmd.mine] = (a) =>
            a['as'] == 'with' ? _page([_row(4, by: 'zed')]) : _page(const []);
        store.switchTo('ana', org: 'other');
        expect(repo.received, isEmpty);
        expect(repo.isLoaded.value, isFalse);
        await _wait(150);
        expect(repo.syncs, 2);
        expect(repo.received.map((t) => t.by), ['zed']);
      },
    );

    test('signing out clears and reads nothing', () async {
      repo = make();
      socket.answers[RecordCmd.mine] = (_) => _page([_row(4)]);
      await repo.syncNow();
      store.switchTo(null);
      expect(repo.received, isEmpty);
      await _wait(100);
      expect(repo.syncs, 1);
    });

    test(
      'a read that was running when the organisation changed is dropped',
      () async {
        repo = make();
        final gate = Completer<void>();
        socket.held[RecordCmd.mine] = gate.future;
        socket.answers[RecordCmd.mine] = (_) => _page([_row(4)]);
        final running = repo.syncNow();
        await _wait(10);
        store.switchTo('ana', org: 'other');
        gate.complete();
        await running;
        expect(repo.received, isEmpty, reason: 'the old organisation is gone');
      },
    );
  });

  group('PagedRead', () {
    test('the page limit is a result, not a silent stop', () async {
      var calls = 0;
      final result = await PagedRead.run(
        label: 'test',
        maxPages: 3,
        page: (offset) async {
          calls++;
          return (received: 2, hasMore: true);
        },
      );
      expect(calls, 3);
      expect(result.isCapped, isTrue);
      expect(result.rows, 6);
      expect(result.isOk, isTrue);
    });

    test('an error is returned with its code and the offset', () async {
      final result = await PagedRead.run(
        label: 'test',
        maxPages: 3,
        page: (offset) async {
          if (offset > 0) throw const SocketCallError('rate_limited');
          return (received: 2, hasMore: true);
        },
      );
      expect(result.error, 'rate_limited');
      expect(result.pages, 1);
      expect(result.isOk, isFalse);
    });

    test('an empty page ends the read even when hasMore says more', () async {
      var calls = 0;
      final result = await PagedRead.run(
        label: 'test',
        maxPages: 5,
        page: (offset) async {
          calls++;
          return (received: 0, hasMore: true);
        },
      );
      expect(calls, 1);
      expect(result.isCapped, isFalse);
    });
  });
}
