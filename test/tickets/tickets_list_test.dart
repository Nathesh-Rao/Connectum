import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/tickets/tickets_controller.dart';
import 'package:connectum/features/tickets/widgets/tickets_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, dynamic> _row(int id) => {
  'id': id,
  'tstruct': 'help_ticket',
  'by': 'rhea',
  'holder': 'ana',
  'ts': 1000 - id,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late TicketRepository repo;
  late TicketsController c;

  setUp(() {
    socket = FakeSocket()..goOnline();
    repo = TicketRepository(socket, FakeStore(user: 'ana'), FakeConversations())
      ..onInit();
  });

  tearDown(() {
    c.onClose();
    repo.onClose();
  });

  List<int> offsets(String as) => [
    for (final x in socket.calls)
      if (x.action == RecordCmd.mine && x.args['as'] == as)
        (x.args['offset'] as int?) ?? 0,
  ];

  test(
    'pages are read while hasMore is true, even when they are short',
    () async {
      // Asked for 100, the server answers 5, then 3, then 2.
      final pages = <int, List<int>>{
        0: [1, 2, 3, 4, 5],
        5: [6, 7, 8],
        8: [9, 10],
      };
      socket.answers[RecordCmd.mine] = (Map<String, dynamic> a) {
        final offset = (a['offset'] as int?) ?? 0;
        final ids = pages[offset] ?? const <int>[];
        return {
          'submissions': [for (final i in ids) _row(i)],
          'structures': _structures,
          'total': 10,
          'hasMore': offset < 8,
          'next': null,
        };
      };
      c = TicketsController(tickets: repo, connectivity: FakeConnectivity());
      await c.load('with');
      expect(c.lists['with']!.items.map((t) => t.id), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
      ]);
      expect(offsets('with'), [0, 5, 8]);
      expect(c.lists['with']!.hasMore.value, isFalse);
      expect(repo.withTotal.value, 10);
    },
  );

  test('raised continues at the server\'s next, with and involved at '
      'offset + rows received', () async {
    // raised scans more rows than it returns: 2 rows back, next is 7.
    socket.answers[RecordCmd.mine] = (Map<String, dynamic> a) {
      final offset = (a['offset'] as int?) ?? 0;
      final isRaised = a['as'] == 'raised';
      final rows = switch (offset) {
        0 => [1, 2],
        7 when isRaised => [3],
        2 when !isRaised => [3],
        _ => const <int>[],
      };
      return {
        'submissions': [for (final i in rows) _row(i)],
        'structures': _structures,
        'total': 3,
        'hasMore': offset == 0,
        'next': offset == 0 && isRaised ? 7 : null,
      };
    };
    c = TicketsController(tickets: repo, connectivity: FakeConnectivity());
    await c.load('raised');
    await c.load('with');
    expect(offsets('raised'), [0, 7]);
    expect(offsets('with'), [0, 2]);
    expect(c.lists['raised']!.items.map((t) => t.id), [1, 2, 3]);
    expect(c.lists['with']!.items.map((t) => t.id), [1, 2, 3]);
  });

  test('every tab asks for its own list: with, raised, involved', () async {
    socket.answers[RecordCmd.mine] = {
      'submissions': [_row(1)],
      'structures': _structures,
      'total': 1,
      'hasMore': false,
      'next': null,
    };
    c = TicketsController(tickets: repo, connectivity: FakeConnectivity())
      ..onInit();
    await _settle();
    expect(TicketsController.tabs, ['with', 'raised', 'involved']);
    for (final as in TicketsController.tabs) {
      expect(offsets(as), isNotEmpty, reason: as);
    }
    expect(
      socket.calls
          .where((x) => x.action == RecordCmd.mine)
          .every((x) => x.args['as'] != 'all'),
      isTrue,
    );
  });

  test(
    'a page that fails half way keeps the rows and offers Show more',
    () async {
      var n = 0;
      socket.answers[RecordCmd.mine] = (Map<String, dynamic> a) {
        if (++n == 2) throw const SocketCallError('timeout');
        return {
          'submissions': [_row(1), _row(2)],
          'structures': _structures,
          'total': 9,
          'hasMore': true,
          'next': null,
        };
      };
      c = TicketsController(tickets: repo, connectivity: FakeConnectivity());
      await c.load('with');
      expect(c.lists['with']!.items.map((t) => t.id), [1, 2]);
      expect(c.lists['with']!.hasMore.value, isTrue);
      expect(c.lists['with']!.loaded, 2);
    },
  );

  test('a record that left the list slides out, the rest stays', () async {
    socket.answers[RecordCmd.mine] = {
      'submissions': [_row(1), _row(2)],
      'structures': _structures,
      'total': 2,
      'hasMore': false,
      'next': null,
    };
    c = TicketsController(tickets: repo, connectivity: FakeConnectivity());
    await c.load('with');
    socket.answers[RecordCmd.mine] = {
      'submissions': [_row(2)],
      'structures': _structures,
      'total': 1,
      'hasMore': false,
      'next': null,
    };
    await c.load('with');
    expect(c.lists['with']!.leaving, {1});
  });

  testWidgets('"With me" shows its total, "Raised by me" never does', (
    tester,
  ) async {
    socket.answers[RecordCmd.mine] = (Map<String, dynamic> a) => {
      'submissions': [_row(1)],
      'structures': _structures,
      // For raised the server only counts the page; it must not be shown.
      'total': a['as'] == 'raised' ? 1 : 42,
      'hasMore': false,
      'next': null,
    };
    c = TicketsController(tickets: repo, connectivity: FakeConnectivity())
      ..onInit();
    await tester.runAsync(_settle);
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(body: TicketsPane(controller: c)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('With me'), findsOneWidget);
    expect(find.text('Raised by me'), findsOneWidget);
    expect(find.text('Involved'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('1'), findsNothing);
    expect(find.text('Row 1'), findsOneWidget);
  });
}
