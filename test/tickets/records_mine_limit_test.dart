import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/features/tickets/tickets_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

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

Map<String, dynamic> _row(int id, {String by = 'ana', String holder = 'bob'}) =>
    {
      'id': id,
      'tstruct': 'help_ticket',
      'by': by,
      'holder': holder,
      'ts': 1000 - id,
      'values': {'title': 'Row $id', 'stage': 'Open'},
    };

/// The server as the BE found it on 16 Nov 2026: `raised` reads a chunk of
/// 200 entries, keeps at most `limit` records and moves past the whole chunk,
/// so the rest of the chunk is lost and `hasMore` is false.
Map<String, dynamic> Function(Map<String, dynamic>) _server(
  List<Map<String, dynamic>> raised,
  List<Map<String, dynamic>> others,
) {
  return (a) {
    final as = a['as'] as String;
    final offset = (a['offset'] as int?) ?? 0;
    final limit = (a['limit'] as int).clamp(1, 200);
    if (as == 'raised') {
      final chunkEnd = offset + 200;
      final kept = raised.skip(offset).take(limit).toList();
      return {
        'submissions': kept,
        'structures': _structures,
        'total': kept.length,
        'hasMore': chunkEnd < raised.length,
        'next': chunkEnd < raised.length ? chunkEnd : null,
      };
    }
    final page = others.skip(offset).take(limit).toList();
    return {
      'submissions': page,
      'structures': _structures,
      'total': others.length,
      'hasMore': offset + page.length < others.length,
      'next': null,
    };
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late TicketRepository repo;

  setUp(() {
    socket = FakeSocket()..goOnline();
    repo = TicketRepository(socket, FakeStore(user: 'ana'), FakeConversations())
      ..onInit();
  });

  tearDown(() => repo.onClose());

  List<Map<String, dynamic>> calls(String as) => [
    for (final c in socket.calls)
      if (c.action == RecordCmd.mine && c.args['as'] == as) c.args,
  ];

  group('the limit rule', () {
    test('raised is always 200, whatever the caller asks for', () {
      expect(RecordLimits.mineLimit('raised', 2), 200);
      expect(RecordLimits.mineLimit('raised', 100), 200);
      expect(RecordLimits.mineLimit('raised', 500), 200);
    });

    test('with, involved and all keep the asked limit within 1-200', () {
      for (final as in ['with', 'involved', 'all']) {
        expect(RecordLimits.mineLimit(as, 100), 100);
        expect(RecordLimits.mineLimit(as, 0), 1);
        expect(RecordLimits.mineLimit(as, 999), 200);
      }
    });

    test('the repository sends 200 for raised even when asked for 2', () async {
      socket.answers[RecordCmd.mine] = _server([_row(1)], [_row(2)]);
      await repo.mine(as: 'raised', limit: 2);
      expect(calls('raised').single['limit'], 200);
    });

    test('with and involved paging is unchanged', () async {
      socket.answers[RecordCmd.mine] = _server(const [], [
        for (var i = 1; i <= 5; i++) _row(i, by: 'rhea', holder: 'ana'),
      ]);
      final p1 = await repo.mine(as: 'with', limit: 2);
      expect(calls('with').single, {'as': 'with', 'limit': 2});
      expect(p1.nextOffset('with', 0), 2);
      final p2 = await repo.mine(as: 'with', offset: 2, limit: 2);
      expect(calls('with').last, {'as': 'with', 'limit': 2, 'offset': 2});
      expect(p2.nextOffset('with', 2), 4);
      await repo.mine(as: 'involved');
      expect(calls('involved').single['limit'], 100);
    });
  });

  group('a server that drops raised records for a small limit', () {
    final raised = [for (var i = 1; i <= 4; i++) _row(i)];

    test(
      'the old request (limit 2) loses two records and says no more',
      () async {
        socket.answers[RecordCmd.mine] = _server(raised, const []);
        final page = await _oldRaisedRead(socket);
        expect(page.map((t) => t), [1, 2]);
      },
    );

    test('the Raised tab reads all four', () async {
      socket.answers[RecordCmd.mine] = _server(raised, const []);
      final c = TicketsController(
        tickets: repo,
        connectivity: FakeConnectivity(),
      );
      addTearDown(c.onClose);
      await c.load('raised');
      expect(c.lists['raised']!.items.map((t) => t.id).toSet(), {1, 2, 3, 4});
      expect(calls('raised').every((a) => a['limit'] == 200), isTrue);
    });

    test('a real next is still followed for raised', () async {
      final many = [for (var i = 1; i <= 250; i++) _row(i)];
      socket.answers[RecordCmd.mine] = _server(many, const []);
      final c = TicketsController(
        tickets: repo,
        connectivity: FakeConnectivity(),
      );
      addTearDown(c.onClose);
      await c.load('raised');
      expect(calls('raised').map((a) => a['offset'] ?? 0), [0, 200]);
      expect(c.lists['raised']!.items.length, 250);
    });
  });
}

/// What the app did before the fix: raised with the page size of 2.
Future<List<int>> _oldRaisedRead(FakeSocket socket) async {
  final reply = await socket.sdCall(RecordCmd.mine, {
    'as': 'raised',
    'limit': 2,
  });
  return [
    for (final r in reply['submissions'] as List) (r as Map)['id'] as int,
  ];
}
