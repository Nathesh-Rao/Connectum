import 'package:connectum/data/models/ticket.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ticket_fixtures.dart';

void main() {
  group('status.mine', () {
    test('with me: the page, the total and the table', () {
      final page = TicketPage.parse(fixtureData('status_mine_with'));
      expect(page.total, 4);
      expect(page.hasMore, isTrue);
      expect(page.tickets, hasLength(1));
      final t = page.tickets.single;
      expect(t.id, 38);
      expect(t.by, 'rhea');
      expect(t.tstruct, 'help_ticket');
      expect(t.isTicket, isTrue);
      final table = t.table!;
      expect(table.field, 'state');
      expect(table.assignee, 'assignee');
      expect(table.completion, 'done');
      expect(table.subject, 'title');
      expect(table.pool, 'support_group');
      expect(table.statuses.map((s) => s.name), [
        'Open',
        'Forwarded',
        'In progress',
        'Completed',
        'Closed',
        'Returned',
        'Dropped',
      ]);
      expect(table.isFinal('Closed'), isTrue);
      expect(table.isFinal('Open'), isFalse);
      expect(table.actions, hasLength(7));
      final send = table.actions.first;
      expect(send.name, 'Send');
      expect(send.who, ['admin', 'assignee']);
      expect(send.assign, 'pick');
      expect(send.remarks, 'required');
      expect(send.asksSendTo, isTrue);
      expect(table.actions.last.who, ['pool']);
    });

    test('raised by me: two forms, the distinct structures', () {
      final page = TicketPage.parse(fixtureData('status_mine_raised'));
      expect(page.total, 5);
      expect(page.hasMore, isFalse);
      expect(page.forms.keys.toSet(), {'help_task', 'help_ticket'});
      expect(page.forms['help_task']!.caption, 'Task');
      expect(page.forms['help_ticket']!.caption, 'Ticket');
      expect(page.forms['help_task']!.table!.pool, isNull);
      expect(page.forms['help_ticket']!.labelOf('title'), 'Title');
      expect(page.forms['help_ticket']!.labelOf('nope'), 'nope');
    });

    test('tolerates missing and unknown fields', () {
      final page = TicketPage.parse({
        'submissions': [
          {
            'id': 1,
            'tstruct': 'x',
            'values': {'a': 1},
            'surprise': true,
          },
          {'no': 'id'},
        ],
        'structures': {
          'x': {
            'status': {
              'field': 'st',
              'statuses': ['A', 'B'],
              'extra': 1,
            },
          },
        },
      });
      expect(page.tickets, hasLength(1));
      expect(page.total, 1);
      expect(page.hasMore, isFalse);
      final t = page.tickets.single;
      expect(t.table!.statuses.map((s) => s.name), ['A', 'B']);
      expect(t.table!.actions, isEmpty);
      expect(TicketPage.parse(const {}).tickets, isEmpty);
    });

    test('a record whose form has no status table is not a ticket', () {
      final t = Ticket.tryParse(
        {'id': 3, 'tstruct': 'leave', 'values': {}},
        TicketForm.parseAll({
          'leave': {'caption': 'Leave', 'fields': {}},
        }),
      )!;
      expect(t.isTicket, isFalse);
    });
  });

  group('drawing rules', () {
    Ticket ticket(Map<String, dynamic> values, {String by = 'rhea'}) {
      final forms = TicketForm.parseAll(
        fixtureData('status_mine_with')['structures'],
      );
      return Ticket(
        id: 7,
        by: by,
        ts: 1,
        tstruct: 'help_ticket',
        values: values,
        form: forms['help_ticket'],
      );
    }

    test('title is the subject', () {
      expect(ticket({'title': 'Lift 2'}).title, 'Lift 2');
    });

    test('title falls back to "<caption> #<id>" when empty or missing', () {
      expect(ticket({'title': '  '}).title, 'Ticket #7');
      expect(ticket({}).title, 'Ticket #7');
    });

    test('title falls back when the form has no subject', () {
      const table = TicketTable(field: 's');
      const form = TicketForm(key: 'k', caption: 'Job', table: table);
      const t = Ticket(
        id: 9,
        by: 'a',
        ts: 0,
        tstruct: 'k',
        values: {'title': 'x'},
        form: form,
      );
      expect(t.title, 'Job #9');
    });

    test('status falls back to the first status of the table', () {
      expect(ticket({}).status, 'Open');
      expect(ticket({'state': ''}).status, 'Open');
      expect(ticket({'state': 'In progress'}).status, 'In progress');
    });

    test('with whom falls back to the person who raised it', () {
      expect(ticket({}).withWhom, 'rhea');
      expect(ticket({'assignee': ''}).withWhom, 'rhea');
      expect(ticket({'assignee': 'ana'}).withWhom, 'ana');
      expect(ticket({'assignee': 'ana'}).isWith('ANA'), isTrue);
    });

    test('completion is 0 to 100', () {
      expect(ticket({}).completion, 0);
      expect(ticket({'done': 40}).completion, 40);
      expect(ticket({'done': '55'}).completion, 55);
      expect(ticket({'done': 400}).completion, 100);
    });

    test('final status and pool', () {
      expect(ticket({'state': 'Closed'}).isFinal, isTrue);
      expect(ticket({'state': 'Unknown'}).isFinal, isFalse);
      expect(ticket({}).hasPool, isFalse);
      expect(ticket({'support_group': 'IT'}).hasPool, isTrue);
    });

    test('waiting for approval: the record status, or an unknown pending', () {
      final t = ticket({});
      expect(t.copyWith(recordStatus: 'pending').isAwaitingApproval, isTrue);
      expect(ticket({'state': 'pending'}).isAwaitingApproval, isTrue);
      expect(ticket({'state': 'Open'}).isAwaitingApproval, isFalse);
    });

    test('an update answer changes status, holder and completion', () {
      final r = TicketUpdateResult.parse(fixtureData('status_update_ok'));
      final t = ticket({'assignee': 'ana', 'state': 'Open'}).applying(r);
      expect(t.status, 'Forwarded');
      expect(t.withWhom, 'bn4jtm');
      expect(t.completion, 0);
    });
  });

  group('status.get', () {
    test('the ticket, isAdmin and inPool', () {
      final d = TicketDetail.tryParse(fixtureData('status_get'))!;
      expect(d.ticket.id, 38);
      expect(d.isAdmin, isFalse);
      expect(d.inPool, isFalse);
      expect(d.ticket.title, 'Lift 2 is stuck on floor 3');
    });

    test('inPool is null when the server does not say', () {
      final data = fixtureData('status_get')..remove('inPool');
      expect(TicketDetail.tryParse(data)!.inPool, isNull);
    });
  });

  group('status.history', () {
    test('oldest first, every field', () {
      final rows = TicketHistoryEntry.parseAll(fixtureData('status_history'));
      expect(rows, hasLength(11));
      expect(rows.first.id, 44);
      expect(rows.first.action, 'Send');
      expect(rows.first.by, 'an4jtm');
      expect(rows.first.fromStatus, 'Open');
      expect(rows.first.toStatus, 'Forwarded');
      expect(rows.first.sentTo, 'bn4jtm');
      expect(rows.first.remarks, 'your area');
      expect(rows.first.isByAdmin, isFalse);
      expect(rows[1].percent, '40');
      expect(rows[3].reason, 'Wrong team');
      expect(rows.last.action, 'Close');
      expect(rows.map((r) => r.id).toList(), [
        for (var i = 44; i <= 54; i++) i,
      ]);
    });

    test('files are read when present, in either shape', () {
      final a = TicketHistoryEntry.tryParse({
        'id': 1,
        'values': {'Action': 'Send'},
        'files': [
          {'id': 'f1', 'name': 'a.png'},
          'f2',
        ],
      })!;
      expect(a.files.map((f) => f.name), ['a.png', 'f2']);
      final b = TicketHistoryEntry.tryParse({
        'id': 2,
        'values': {
          'Action': 'Send',
          'Files': [
            {'id': 'x'},
          ],
        },
      })!;
      expect(b.files.single.id, 'x');
      expect(TicketHistoryEntry.tryParse({'id': 3})!.files, isEmpty);
    });
  });

  group('status.update answer', () {
    test('ok', () {
      final r = TicketUpdateResult.parse(fixtureData('status_update_ok'));
      expect(r.status, 'Forwarded');
      expect(r.assignee, 'bn4jtm');
      expect(r.completion, 0);
      expect(r.record, 44);
      expect(r.ticket, 42);
      expect(r.isRepeated, isFalse);
    });

    test('a repeat is marked', () {
      expect(
        TicketUpdateResult.parse({'status': 'A', 'repeated': true}).isRepeated,
        isTrue,
      );
    });
  });

  test('ticket_assigned event', () {
    final e = TicketAssigned.tryParse({
      'id': 5,
      'tstruct': 'help_ticket',
      'action': 'Raised',
      'by': 'rhea',
    })!;
    expect(e.id, 5);
    expect(e.isRaised, isTrue);
    expect(TicketAssigned.tryParse({'tstruct': 'x'}), isNull);
  });
}
