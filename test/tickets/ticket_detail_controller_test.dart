import 'dart:async';

import 'package:connectum/data/models/record_state.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/tickets/models/ticket_input.dart';
import 'package:connectum/features/tickets/ticket_action_form.dart';
import 'package:connectum/features/tickets/ticket_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import 'ticket_fixtures.dart';

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late FakeStore store;
  late TicketRepository repo;
  late TicketDetailController c;

  Map<String, dynamic> actions({Map<String, dynamic> extra = const {}}) => {
    ...fixtureData('record_actions'),
    ...extra,
  };

  Future<void> start({Map<String, dynamic> extra = const {}}) async {
    socket.answers[RecordCmd.get] = {
      'submission': {
        'id': 24,
        'tstruct': 'help_ticket',
        'by': 'ana',
        'values': {'title': 'Printer', 'stage': 'Open'},
      },
    };
    socket.answers[RecordCmd.actions] = actions(extra: extra);
    socket.answers[RecordCmd.history] = fixtureData('submission_history');
    c = TicketDetailController(
      ticketId: 24,
      tickets: repo,
      files: FakeFiles(),
      connectivity: FakeConnectivity(),
      busyDelay: Duration.zero,
      coolDown: const Duration(milliseconds: 40),
    )..onInit();
    await _settle();
  }

  TicketActionForm statusForm({String to = 'In progress'}) =>
      c.newForm(RecordActionItem.status)
        ..statusPick.value = to
        ..percent.value = 30;

  Map<String, dynamic> lastStatus() =>
      socket.calls.lastWhere((x) => x.action == RecordCmd.status).args;

  setUp(() {
    socket = FakeSocket()..goOnline();
    store = FakeStore(user: 'ana');
    repo = TicketRepository(socket, store, FakeConversations())..onInit();
  });

  tearDown(() {
    c.onClose();
    repo.onClose();
  });

  test('the record, its actions and its history are read on open', () async {
    await start();
    expect(c.viewState.value.name, 'content');
    expect(c.items.map((i) => i.id), ['send', 'status']);
    expect(c.status, 'Open');
    expect(c.history.value!.events, hasLength(4));
    expect(c.holders, ['ana']);
  });

  group('status', () {
    test('the payload carries expected and a request id', () async {
      await start();
      socket.answers[RecordCmd.status] = fixtureData('record_status_ok');
      final form = statusForm()
        ..commentsText.value = 'Called'
        ..hoursText.value = '2.5';
      expect(await c.submit(form), ActionResult.done);
      final args = lastStatus();
      expect(args['id'], 24);
      expect(args['status'], 'In progress');
      expect(args['percent'], 30);
      expect(args['comments'], 'Called');
      expect(args['hours'], '2.5');
      expect(args['expected'], {'status': 'Open', 'holder': 'ana'});
      expect((args['requestId'] as String).length, greaterThan(20));
      expect((args['requestId'] as String).length, lessThanOrEqualTo(100));
      expect(form.requestId, isNull);
      expect(c.isBusy.value, isFalse);
    });

    test('after an action the record and its history are read again', () async {
      await start();
      final actionsBefore = socket.count(RecordCmd.actions);
      final historyBefore = socket.count(RecordCmd.history);
      socket.answers[RecordCmd.status] = fixtureData('record_status_ok');
      await c.submit(statusForm());
      await _settle();
      expect(socket.count(RecordCmd.actions), greaterThan(actionsBefore));
      expect(socket.count(RecordCmd.history), greaterThan(historyBefore));
    });

    test('a lost answer: the retry carries the same request id', () async {
      await start();
      final form = statusForm();
      socket.answers[RecordCmd.status] = const SocketCallError('timeout');
      expect(await c.submit(form), ActionResult.failed);
      final first = lastStatus()['requestId'];
      expect(form.requestId, first);
      expect(c.isBusy.value, isFalse);

      socket.answers[RecordCmd.status] = {
        ...fixtureData('record_status_ok'),
        'repeated': true,
      };
      expect(await c.submit(form), ActionResult.done);
      expect(lastStatus()['requestId'], first);
      expect(socket.count(RecordCmd.status), 2);
      expect(form.requestId, isNull);
    });

    test('a new intent is a new request id', () async {
      await start();
      socket.answers[RecordCmd.status] = fixtureData('record_status_ok');
      await c.submit(statusForm());
      final first = lastStatus()['requestId'];
      await c.submit(statusForm(to: 'Done'));
      expect(lastStatus()['requestId'], isNot(first));
    });

    test(
      'stale: the input stays, the record is read again, a new id next',
      () async {
        await start();
        final form = statusForm()..commentsText.value = 'Mine';
        socket.answers[RecordCmd.status] = const SocketCallError(
          'stale',
          'This record was updated by someone else. Reload to see the latest.',
        );
        final before = socket.count(RecordCmd.actions);
        expect(await c.submit(form), ActionResult.failed);
        await _settle();
        expect(form.commentsText.value, 'Mine');
        expect(form.statusPick.value, 'In progress');
        expect(form.error.value, contains('updated by someone else'));
        expect(form.requestId, isNull);
        expect(socket.count(RecordCmd.actions), greaterThan(before));
      },
    );

    test('busy: one automatic retry, same request id, then success', () async {
      await start();
      var n = 0;
      socket.answers[RecordCmd.status] = (Map<String, dynamic> a) {
        if (++n == 1) {
          throw const SocketCallError(
            'busy',
            'This record is being updated. Try again in a moment.',
          );
        }
        return fixtureData('record_status_ok');
      };
      final form = statusForm();
      expect(await c.submit(form), ActionResult.done);
      final ids = [
        for (final x in socket.calls)
          if (x.action == RecordCmd.status) x.args['requestId'],
      ];
      expect(ids, hasLength(2));
      expect(ids.first, ids.last);
    });

    test('busy twice: the notice stays and the request id is kept', () async {
      await start();
      socket.answers[RecordCmd.status] = const SocketCallError(
        'busy',
        'This record is being updated. Try again in a moment.',
      );
      final form = statusForm();
      expect(await c.submit(form), ActionResult.failed);
      expect(socket.count(RecordCmd.status), 2);
      expect(form.requestId, isNotNull);
      expect(form.error.value, contains('Try again in a moment'));
    });

    test(
      'rate_limited: the buttons wait a little, nothing is retried',
      () async {
        await start();
        socket.answers[RecordCmd.status] = const SocketCallError(
          'rate_limited',
          'Too many commands.',
        );
        final form = statusForm();
        expect(await c.submit(form), ActionResult.failed);
        expect(c.isCooling.value, isTrue);
        expect(await c.submit(form), ActionResult.failed);
        expect(socket.count(RecordCmd.status), 1);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(c.isCooling.value, isFalse);
      },
    );

    test('not_found: the record is gone and the lists refresh', () async {
      await start();
      var refreshed = 0;
      final sub = repo.refreshes.listen((_) => refreshed++);
      socket.answers[RecordCmd.status] = const SocketCallError(
        'not_found',
        'No such record.',
      );
      expect(await c.submit(statusForm()), ActionResult.gone);
      expect(c.isGone.value, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(refreshed, 1);
      await sub.cancel();
    });

    test('forbidden shows the server text and reads again', () async {
      await start();
      socket.answers[RecordCmd.status] = const SocketCallError(
        'forbidden',
        'Only the person it is with can do this.',
      );
      final before = socket.count(RecordCmd.actions);
      final form = statusForm();
      expect(await c.submit(form), ActionResult.failed);
      await _settle();
      expect(form.error.value, 'Only the person it is with can do this.');
      expect(socket.count(RecordCmd.actions), greaterThan(before));
    });

    test('invalid shows the message and nothing else', () async {
      await start();
      socket.answers[RecordCmd.status] = const SocketCallError(
        'invalid',
        'It is already Open.',
      );
      final form = statusForm(to: 'Open');
      final before = socket.count(RecordCmd.actions);
      expect(await c.submit(form), ActionResult.failed);
      await _settle();
      expect(form.error.value, 'It is already Open.');
      expect(socket.count(RecordCmd.actions), before);
    });

    test('a required field from record.actions blocks the send', () async {
      await start(extra: {'commentsRequired': true});
      final form = statusForm();
      expect(await c.submit(form), ActionResult.failed);
      expect(form.error.value, 'Add your comments.');
      expect(socket.count(RecordCmd.status), 0);
    });

    test('a disabled item never sends and shows its why', () async {
      await start(
        extra: {
          'items': [
            {
              'id': 'status',
              'label': 'Update status',
              'enabled': false,
              'why': 'This record is waiting for approval.',
            },
          ],
        },
      );
      final form = statusForm();
      expect(await c.submit(form), ActionResult.failed);
      expect(form.error.value, 'This record is waiting for approval.');
      expect(socket.count(RecordCmd.status), 0);
    });
  });

  group('send', () {
    test('via user carries the person and the expected state', () async {
      await start();
      socket.answers[RecordCmd.send] = fixtureData('record_send_ok');
      final form = c.newForm(RecordActionItem.send)
        ..person.value = const RecordPerson(username: 'ben', name: 'Ben Iyer')
        ..reasonText.value = 'Needs the technician';
      expect(await c.submit(form), ActionResult.done);
      final args = socket.calls
          .lastWhere((x) => x.action == RecordCmd.send)
          .args;
      expect(args['via'], 'user');
      expect(args['person'], 'ben');
      expect(args['reason'], 'Needs the technician');
      expect(args['expected'], {'status': 'Open', 'holder': 'ana'});
      expect(args['requestId'], isA<String>());
      expect(c.ticket.value!.holder, 'ben');
    });

    test('nobody chosen: nothing is sent', () async {
      await start();
      final form = c.newForm(RecordActionItem.send);
      expect(await c.submit(form), ActionResult.failed);
      expect(form.error.value, RecordValidation.sendToRequired);
      expect(socket.count(RecordCmd.send), 0);
    });

    test('stale on send keeps the sheet and its input', () async {
      await start();
      socket.answers[RecordCmd.send] = const SocketCallError(
        'stale',
        'This record was updated by someone else. Reload to see the latest.',
      );
      final form = c.newForm(RecordActionItem.send)
        ..via.value = 'initiator'
        ..remarksText.value = 'please';
      expect(await c.submit(form), ActionResult.failed);
      expect(form.remarksText.value, 'please');
      expect(form.via.value, 'initiator');
    });
  });

  test('the record gone on open shows the gone state', () async {
    socket.answers[RecordCmd.get] = const SocketCallError(
      'not_found',
      'No such record.',
    );
    socket.answers[RecordCmd.actions] = const SocketCallError(
      'not_found',
      'No such record.',
    );
    socket.answers[RecordCmd.history] = const SocketCallError(
      'not_found',
      'No such record.',
    );
    c = TicketDetailController(
      ticketId: 24,
      tickets: repo,
      files: FakeFiles(),
      connectivity: FakeConnectivity(),
    )..onInit();
    await _settle();
    expect(c.isGone.value, isTrue);
  });

  test(
    'an event during a read asks for one more read, not two at once',
    () async {
      await start();
      final gate = Completer<void>();
      socket.held[RecordCmd.actions] = gate.future;
      final before = socket.count(RecordCmd.actions);
      unawaited(c.reload());
      unawaited(c.reload());
      unawaited(c.reload());
      await _settle();
      expect(socket.count(RecordCmd.actions) - before, 1);
      socket.held.remove(RecordCmd.actions);
      gate.complete();
      await _settle();
      expect(socket.count(RecordCmd.actions) - before, 2);
    },
  );
}
