import 'package:connectum/data/models/record_state.dart';
import 'package:connectum/data/models/ticket.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ticket_fixtures.dart';

void main() {
  group('records.mine', () {
    test(
      'rows carry holder, assignor and completion; the form only a status',
      () {
        final page = TicketPage.parse(fixtureData('records_mine_with'));
        expect(page.tickets, hasLength(1));
        final t = page.tickets.single;
        expect(t.id, 24);
        expect(t.holder, 'ben');
        expect(t.assignor, 'ana');
        expect(t.completion, 30);
        expect(t.participants, ['ana', 'ben']);
        expect(t.hasStatus, isTrue);
        expect(t.status, 'In progress');
        expect(t.isFinal, isFalse);
        expect(t.table!.statuses.map((s) => s.name), [
          'Open',
          'In progress',
          'Done',
        ]);
        expect(t.table!.isFinal('Done'), isTrue);
        expect(t.table!.firstStatus, 'Open');
        expect(t.form!.hasThread, isTrue);
        expect(page.hasMore, isFalse);
      },
    );

    test('no old actions table is read: only field, statuses and final', () {
      final page = TicketPage.parse(fixtureData('records_mine_with'));
      expect(page.forms['help_ticket']!.table!.field, 'stage');
    });

    test('the hidden fields of the status are not record values', () {
      final t = TicketPage.parse(
        fixtureData('records_mine_with'),
      ).tickets.single;
      expect(
        t.table!.headerFields,
        containsAll([
          'stage',
          'stage_completion',
          'stage_comments',
          'stage_files',
          'stage_hours',
        ]),
      );
    });

    test('a page can be short while hasMore is true', () {
      final page = TicketPage.parse({
        'submissions': [
          {'id': 1, 'tstruct': 'a', 'values': {}},
        ],
        'structures': <String, dynamic>{},
        'total': 250,
        'hasMore': true,
        'next': null,
      });
      expect(page.tickets, hasLength(1));
      expect(page.hasMore, isTrue);
      expect(page.total, 250);
    });

    test('a record waiting for approval is recognised', () {
      final t = Ticket.tryParse({
        'id': 5,
        'tstruct': 'a',
        'status': 'pending',
        'values': {},
      }, const {})!;
      expect(t.isAwaitingApproval, isTrue);
    });
  });

  group('record.actions', () {
    test('items, holder, statuses and the required flags', () {
      final s = RecordState.parse(fixtureData('record_actions'));
      expect(s.items.map((i) => i.id), ['send', 'status']);
      expect(s.hasSend, isTrue);
      expect(s.hasStatus, isTrue);
      expect(s.holder, 'ana');
      expect(s.initiator, 'ana');
      expect(s.assignor, '');
      expect(s.status, 'Open');
      expect(s.statuses, ['Open', 'In progress', 'Done']);
      expect(s.finalStatuses, ['Done']);
      expect(s.isCommentsRequired, isFalse);
      expect(s.hours, isNull);
      expect(s.completion, isNull);
      expect(s.expected, {'status': 'Open', 'holder': 'ana'});
    });

    test('a disabled item keeps its why; claimants, hours and files parse', () {
      final s = RecordState.parse({
        'items': [
          {
            'id': 'status',
            'label': 'Update status',
            'enabled': false,
            'why': 'Nope.',
          },
        ],
        'holder': '',
        'claimants': ['ben', 'sam'],
        'status': 'Open',
        'statuses': ['Open'],
        'final': <String>[],
        'completion': 40,
        'hours': '2.5',
        'commentsRequired': true,
        'completionRequired': true,
        'hoursRequired': true,
        'filesRequired': true,
        'isAdmin': true,
        'hasRules': true,
        'lastUpdate': {'by': 'x'},
        'files': ['f1'],
      });
      final i = s.item('status')!;
      expect(i.isEnabled, isFalse);
      expect(i.why, 'Nope.');
      expect(s.hasSend, isFalse);
      expect(s.claimants, ['ben', 'sam']);
      expect(s.completion, 40);
      expect(s.hours, '2.5');
      expect(
        s.isCompletionRequired && s.isHoursRequired && s.isFilesRequired,
        isTrue,
      );
      expect(s.isAdmin && s.hasRules, isTrue);
      expect(s.files, ['f1']);
      expect(s.expected, {'status': 'Open'});
    });
  });

  group('patches', () {
    test('record.status', () {
      final p = RecordPatch.parse(fixtureData('record_status_ok'));
      expect(p.id, 24);
      expect(p.holder, 'ben');
      expect(p.status, 'In progress');
      expect(p.completion, 30);
      expect(p.hours, '2.5');
      expect(p.isFinal, isFalse);
      expect(p.assignor, isNull);
      expect(p.isRepeated, isFalse);
    });

    test('record.send carries the assignor; repeated:true is read', () {
      final p = RecordPatch.parse({
        ...fixtureData('record_send_ok'),
        'repeated': true,
      });
      expect(p.assignor, 'ana');
      expect(p.holder, 'ben');
      expect(p.isRepeated, isTrue);
    });

    test('the patch moves the known record', () {
      final t = TicketPage.parse(
        fixtureData('records_mine_with'),
      ).tickets.single;
      final next = t.applying(
        const RecordPatch(
          id: 24,
          holder: 'sam',
          assignor: 'ben',
          status: 'Done',
          completion: 100,
          isFinal: true,
        ),
      );
      expect(next.holder, 'sam');
      expect(next.assignor, 'ben');
      expect(next.completion, 100);
      expect(next.status, 'Done');
      expect(next.isFinal, isTrue);
    });
  });

  group('submission.history', () {
    test('events oldest first, names, fields and the op fields', () {
      final h = RecordHistory.parse(fixtureData('submission_history'));
      expect(h.events.map((e) => e.op), [
        'created',
        'sent',
        'status',
        'status',
      ]);
      expect(h.nameOf('ana'), 'Ana Rao');
      expect(h.nameOf('zed'), 'zed');
      expect(h.fields['stage'], 'Stage');
      expect(h.caption, 'Ticket');
      final sent = h.events[1];
      expect(sent.to, ['ben']);
      expect(sent.via, 'user');
      expect(sent.fromHolder, 'ana');
      expect(sent.reason, 'Needs the technician');
      expect(sent.isAsAdmin, isFalse);
      final done = h.events.last;
      expect(done.fromStatus, 'In progress');
      expect(done.toStatus, 'Done');
      expect(done.completion, '100');
      expect(done.isFinal, isTrue);
    });

    test('every op the server names parses, and edited keeps its changes', () {
      for (final op in RecordEvent.ops) {
        expect(RecordEvent.tryParse({'id': 1, 'op': op})!.op, op);
      }
      final e = RecordEvent.tryParse({
        'id': 1,
        'op': 'edited',
        'changes': [
          {'field': 'title', 'from': 'a', 'to': 'b'},
        ],
        'claimed': true,
      })!;
      expect(e.changes.single.field, 'title');
      expect(e.changes.single.to, 'b');
      expect(e.isClaimed, isTrue);
    });

    test('files come as a map by id', () {
      final h = RecordHistory.parse({
        'events': <Object>[],
        'files': {
          'f1': {
            'id': 'f1',
            'name': 'a.pdf',
            'size': 10,
            'mime': 'application/pdf',
          },
        },
      });
      expect(h.files['f1']!.name, 'a.pdf');
      expect(h.files['f1']!.size, 10);
    });
  });

  group('helpers', () {
    test('targets, people and thread', () {
      final t = RecordTargets.parse(fixtureData('record_targets'));
      expect(t.isUnrestricted, isTrue);
      expect(t.initiator, 'ana');
      expect(t.isBlocked, isFalse);
      final p = RecordPerson.parseAll(fixtureData('record_people'));
      expect(p.single.username, 'ben');
      expect(p.single.designation, 'Analyst');
      final th = RecordThread.tryParse({
        'conversation': 'group:rec-ticket-12',
        'id': 12,
        'title': 'Ticket #12',
      })!;
      expect(th.conversation, 'group:rec-ticket-12');
      expect(RecordThread.tryParse(<String, dynamic>{}), isNull);
    });
  });
}
