import 'dart:async';

import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/tickets/ticket_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import 'ticket_fixtures.dart';

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late FakeStore store;
  late TicketRepository repo;
  late TicketDetailController c;

  Map<String, dynamic> ok(String status) => {
    'assignee': 'ana',
    'byAdmin': false,
    'completion': 30,
    'record': 39,
    'status': status,
    'ticket': 38,
  };

  Future<void> start() async {
    socket.answers['status.mine'] = fixtureData('status_mine_with');
    socket.answers['status.get'] = fixtureData('status_get');
    socket.answers['status.history'] = fixtureData('status_history');
    await repo.mine(as: 'with');
    c = TicketDetailController(
      ticketId: 38,
      tickets: repo,
      people: FakeGroups(),
      files: FakeFiles(),
      connectivity: FakeConnectivity(),
    )..onInit();
    await _settle();
  }

  TicketAction action(String name) =>
      c.actions.firstWhere((a) => a.name == name);

  Map<String, dynamic> lastUpdate() =>
      socket.calls.lastWhere((x) => x.action == 'status.update').args;

  setUp(() {
    socket = FakeSocket()..goOnline();
    store = FakeStore(user: 'ana');
    repo = TicketRepository(socket, store, FakeConversations())..onInit();
  });

  tearDown(() {
    c.onClose();
    repo.onClose();
  });

  test(
    'the assignee sees her actions; the payload carries expected and a request id',
    () async {
      await start();
      expect(c.actions.map((a) => a.name), contains('Status update'));
      final form = c.newForm(action('Status update'))..percent.value = 30;
      socket.answers['status.update'] = ok('In progress');
      expect(await c.submit(form), isTrue);
      final args = lastUpdate();
      expect(args['id'], 38);
      expect(args['action'], 'Status update');
      expect(args['expected'], {'status': 'Open', 'assignee': 'ana'});
      expect(args['percent'], 30);
      expect(args['requestId'], isA<String>());
      expect((args['requestId'] as String).length, greaterThan(20));
      expect(form.requestId, isNull);
      expect(c.isBusy.value, isFalse);
    },
  );

  test('a lost answer: the retry carries the same request id', () async {
    await start();
    final form = c.newForm(action('Status update'));
    socket.answers['status.update'] = const SocketCallError('timeout');
    expect(await c.submit(form), isFalse);
    final first = lastUpdate()['requestId'];
    expect(form.requestId, first);
    expect(c.isBusy.value, isFalse);

    socket.answers['status.update'] = {...ok('In progress'), 'repeated': true};
    expect(await c.submit(form), isTrue);
    expect(lastUpdate()['requestId'], first);
    expect(socket.count('status.update'), 2);
    expect(form.requestId, isNull);
  });

  test('a new press on a new form is a new request id', () async {
    await start();
    socket.answers['status.update'] = ok('In progress');
    await c.submit(c.newForm(action('Status update')));
    final first = lastUpdate()['requestId'];
    await c.submit(c.newForm(action('Status update')));
    expect(lastUpdate()['requestId'], isNot(first));
  });

  test(
    'airplane mode right after the tap: not_connected keeps the id too',
    () async {
      await start();
      final form = c.newForm(action('Status update'));
      socket.goOffline();
      expect(await c.submit(form), isFalse);
      expect(socket.count('status.update'), 0);
      socket.goOnline();
      socket.answers['status.update'] = ok('In progress');
      expect(await c.submit(form), isTrue);
      expect(socket.count('status.update'), 1);
    },
  );

  test(
    'stale: told verbatim, the ticket is read again, next send is a new id',
    () async {
      await start();
      final form = c.newForm(action('Status update'));
      socket.answers['status.update'] = const SocketCallError(
        'stale',
        'This ticket was updated by someone else. Reload to see the latest.',
      );
      final reads = socket.count('status.get');
      expect(await c.submit(form), isFalse);
      final first = lastUpdate()['requestId'];
      await _settle();
      expect(socket.count('status.get'), greaterThan(reads));
      expect(form.requestId, isNull);
      socket.answers['status.update'] = ok('In progress');
      await c.submit(form);
      expect(lastUpdate()['requestId'], isNot(first));
    },
  );

  test('forbidden reads again; busy and rate_limited keep the id', () async {
    await start();
    final form = c.newForm(action('Status update'));
    socket.answers['status.update'] = const SocketCallError(
      'rate_limited',
      'Too many commands -- slow down and retry.',
    );
    await c.submit(form);
    final kept = form.requestId;
    expect(kept, isNotNull);
    socket.answers['status.update'] = const SocketCallError('busy', 'Busy.');
    await c.submit(form);
    expect(form.requestId, kept);
    socket.answers['status.update'] = const SocketCallError(
      'forbidden',
      'You cannot do this on this ticket.',
    );
    final reads = socket.count('status.get');
    await c.submit(form);
    await _settle();
    expect(form.requestId, isNull);
    expect(socket.count('status.get'), greaterThan(reads));
  });

  test('not_found: the ticket is gone', () async {
    await start();
    socket.answers['status.update'] = const SocketCallError(
      'not_found',
      'No such ticket.',
    );
    await c.submit(c.newForm(action('Status update')));
    expect(c.isGone.value, isTrue);
  });

  test('a double tap sends one update; the spinner always ends', () async {
    await start();
    final gate = Completer<void>();
    socket.held['status.update'] = gate.future;
    socket.answers['status.update'] = ok('In progress');
    final form = c.newForm(action('Status update'));
    final a = c.submit(form);
    final b = c.submit(form);
    expect(c.isBusy.value, isTrue);
    gate.complete();
    expect(await b, isFalse);
    expect(await a, isTrue);
    expect(socket.count('status.update'), 1);
    expect(c.isBusy.value, isFalse);
  });

  test(
    'required remarks and reason block the send before the network',
    () async {
      await start();
      final form = c.newForm(action('Return'));
      expect(await c.submit(form), isFalse);
      expect(socket.count('status.update'), 0);
      expect(form.error.value, isNotNull);
    },
  );

  test(
    'the ticket list of another person does not leak into this one',
    () async {
      await start();
      expect(repo.known(38), isNotNull);
      expect(repo.withTotal.value, 4);
      store.switchTo('someone-else');
      expect(repo.known(38), isNull);
      expect(repo.withTotal.value, 0);
    },
  );
}
