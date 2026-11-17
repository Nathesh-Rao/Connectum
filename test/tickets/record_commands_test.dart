import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/tickets/models/ticket_input.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import 'ticket_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late FakeStore store;
  late TicketRepository repo;

  Map<String, dynamic> lastArgs(String action) =>
      socket.calls.lastWhere((c) => c.action == action).args;

  setUp(() {
    socket = FakeSocket()..goOnline();
    store = FakeStore(user: 'ana');
    repo = TicketRepository(socket, store, FakeConversations())..onInit();
  });

  tearDown(() => repo.onClose());

  group('request shapes', () {
    test('records.mine: as, limit and offset only when there is one', () async {
      socket.answers[RecordCmd.mine] = fixtureData('records_mine_with');
      await repo.mine(as: 'with');
      expect(lastArgs(RecordCmd.mine), {'as': 'with', 'limit': 100});
      await repo.mine(as: 'raised', offset: 100);
      expect(lastArgs(RecordCmd.mine), {
        'as': 'raised',
        'limit': 200,
        'offset': 100,
      });
      await repo.mine(as: 'involved');
      expect(lastArgs(RecordCmd.mine)['as'], 'involved');
    });

    test(
      'only "with" feeds the badge; the raised total is never kept',
      () async {
        socket.answers[RecordCmd.mine] = {
          ...fixtureData('records_mine_with'),
          'total': 7,
        };
        await repo.mine(as: 'with');
        expect(repo.withTotal.value, 7);
        socket.answers[RecordCmd.mine] = {
          ...fixtureData('records_mine_raised'),
          'total': 1,
        };
        await repo.mine(as: 'raised');
        expect(repo.withTotal.value, 7);
      },
    );

    test('a record is read with submission.get and record.actions', () async {
      socket.answers[RecordCmd.get] = {
        'submission': {
          'id': 24,
          'tstruct': 'help_ticket',
          'by': 'ana',
          'values': {'title': 'Printer', 'stage': 'Open'},
        },
      };
      socket.answers[RecordCmd.actions] = fixtureData('record_actions');
      final d = await repo.get(24);
      expect(lastArgs(RecordCmd.get), {'id': 24});
      expect(lastArgs(RecordCmd.actions), {'id': 24});
      expect(d.ticket.id, 24);
      expect(d.ticket.holder, 'ana');
      expect(d.state.hasStatus, isTrue);
      expect(repo.known(24)!.holder, 'ana');
    });

    test('submission.history', () async {
      socket.answers[RecordCmd.history] = fixtureData('submission_history');
      final h = await repo.history(24);
      expect(lastArgs(RecordCmd.history), {'id': 24});
      expect(h.events, hasLength(4));
      expect(repo.nameOf('ben'), 'Ben Iyer');
    });

    test('record.status carries only what was given', () async {
      socket.answers[RecordCmd.status] = fixtureData('record_status_ok');
      final patch = await repo.setStatus(
        RecordPayload.status(
          id: 24,
          input: const StatusInput(
            status: 'In progress',
            comments: ' Called ',
            percent: 30,
            hours: '2,5',
            files: ['f1'],
          ),
          requestId: 'r-1',
          expected: const {'status': 'Open', 'holder': 'ana'},
        ),
      );
      expect(lastArgs(RecordCmd.status), {
        'id': 24,
        'status': 'In progress',
        'comments': 'Called',
        'percent': 30,
        'hours': '2.5',
        'files': ['f1'],
        'expected': {'status': 'Open', 'holder': 'ana'},
        'requestId': 'r-1',
      });
      expect(patch.status, 'In progress');
      await repo.setStatus(
        RecordPayload.status(
          id: 24,
          input: const StatusInput(status: 'Done'),
          requestId: 'r-2',
        ),
      );
      expect(lastArgs(RecordCmd.status), {
        'id': 24,
        'status': 'Done',
        'requestId': 'r-2',
      });
    });

    test('record.send for every via', () async {
      socket.answers[RecordCmd.send] = fixtureData('record_send_ok');
      Future<Map<String, dynamic>> go(SendInput i) async {
        await repo.send(RecordPayload.send(id: 24, input: i, requestId: 'r-1'));
        return lastArgs(RecordCmd.send);
      }

      expect(
        await go(const SendInput(via: 'user', person: 'ben', reason: 'Why')),
        {
          'id': 24,
          'via': 'user',
          'person': 'ben',
          'reason': 'Why',
          'requestId': 'r-1',
        },
      );
      expect(
        await go(const SendInput(via: 'designation', value: 'Technician')),
        {
          'id': 24,
          'via': 'designation',
          'value': 'Technician',
          'requestId': 'r-1',
        },
      );
      expect(
        await go(
          const SendInput(via: 'category', value: 'Customer', remarks: 'x'),
        ),
        {
          'id': 24,
          'via': 'category',
          'value': 'Customer',
          'remarks': 'x',
          'requestId': 'r-1',
        },
      );
      expect(await go(const SendInput(via: 'initiator')), {
        'id': 24,
        'via': 'initiator',
        'requestId': 'r-1',
      });
      expect(await go(const SendInput(via: 'assignor', files: ['f'])), {
        'id': 24,
        'via': 'assignor',
        'files': ['f'],
        'requestId': 'r-1',
      });
    });

    test('record.targets, record.people and record.thread', () async {
      socket.answers[RecordCmd.targets] = fixtureData('record_targets');
      socket.answers[RecordCmd.people] = fixtureData('record_people');
      socket.answers[RecordCmd.thread] = {
        'conversation': 'group:rec-help_ticket-24',
        'id': 24,
        'title': 'Printer',
      };
      expect((await repo.targets(24)).isUnrestricted, isTrue);
      expect(lastArgs(RecordCmd.targets), {'id': 24});
      final people = await repo.people(24, q: ' be ', designation: 'Analyst');
      expect(people.single.name, 'Ben Iyer');
      expect(lastArgs(RecordCmd.people), {
        'id': 24,
        'q': 'be',
        'designation': 'Analyst',
      });
      await repo.people(24);
      expect(lastArgs(RecordCmd.people), {'id': 24});
      expect((await repo.thread(24))!.conversation, 'group:rec-help_ticket-24');
    });

    test('the server refusing is thrown with its code', () async {
      socket.answers[RecordCmd.status] = const SocketCallError(
        'forbidden',
        'Only the person it is with can do this.',
      );
      await expectLater(
        repo.setStatus({'id': 24, 'status': 'Done'}),
        throwsA(
          isA<SocketCallError>().having((e) => e.code, 'code', 'forbidden'),
        ),
      );
    });
  });

  group('events', () {
    test('a burst becomes one refresh after 300 ms', () {
      fakeAsync((async) {
        var n = 0;
        repo.refreshes.listen((_) => n++);
        for (final e in [
          'submissions_changed',
          'ticket_assigned',
          'submissions_changed',
        ]) {
          repo.onEvent({
            'type': 'sd_event',
            'event': e,
            'data': {'id': 1, 'tstruct': 'a', 'action': 'Send', 'by': 'x'},
          });
        }
        async.elapse(const Duration(milliseconds: 299));
        expect(n, 0);
        async.elapse(const Duration(milliseconds: 2));
        expect(n, 1);
      });
    });

    test('ticket_assigned also tells who it came from', () async {
      final got = <TicketAssigned>[];
      repo.assigned.listen(got.add);
      repo.onEvent({
        'type': 'sd_event',
        'event': 'ticket_assigned',
        'data': {'id': 9, 'tstruct': 'help', 'action': 'Send', 'by': 'rhea'},
      });
      await Future<void>.delayed(Duration.zero);
      expect(got.single.id, 9);
      expect(got.single.by, 'rhea');
    });

    test('other events do nothing', () {
      fakeAsync((async) {
        var n = 0;
        repo.refreshes.listen((_) => n++);
        repo.onEvent({'type': 'sd_event', 'event': 'task_updated'});
        repo.onEvent({'type': 'message'});
        async.elapse(const Duration(seconds: 1));
        expect(n, 0);
      });
    });

    test('form_message_updated refreshes too', () {
      fakeAsync((async) {
        var n = 0;
        repo.refreshes.listen((_) => n++);
        repo.onEvent({'type': 'sd_event', 'event': 'form_message_updated'});
        async.elapse(const Duration(milliseconds: 301));
        expect(n, 1);
      });
    });
  });

  test('no command name of the old flow is in RecordCmd', () {
    const live = [
      RecordCmd.mine,
      RecordCmd.get,
      RecordCmd.history,
      RecordCmd.actions,
      RecordCmd.status,
      RecordCmd.send,
      RecordCmd.targets,
      RecordCmd.people,
      RecordCmd.thread,
    ];
    for (final old in RecordCmd.removed) {
      expect(live, isNot(contains(old)));
    }
    expect(TaskCmd.get, 'task.get');
  });
}
