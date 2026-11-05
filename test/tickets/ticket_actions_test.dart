import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/features/tickets/models/ticket_actions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ticket_fixtures.dart';

final _forms = TicketForm.parseAll(
  fixtureData('status_mine_with')['structures'],
);

Ticket ticket({
  String by = 'rhea',
  Map<String, dynamic> values = const {},
  String recordStatus = '',
  int id = 38,
}) => Ticket(
  id: id,
  by: by,
  ts: 1,
  tstruct: 'help_ticket',
  values: {'title': 'Lift', ...values},
  recordStatus: recordStatus,
  form: _forms['help_ticket'],
);

List<String> names(Ticket t, String me, {bool isAdmin = false, bool? inPool}) =>
    [
      for (final a in TicketActions.of(t, me, isAdmin: isAdmin, inPool: inPool))
        a.name,
    ];

void main() {
  test('the assignee: Send, Status update, Complete, Return, Drop', () {
    final t = ticket(values: {'assignee': 'ana', 'state': 'Open'});
    expect(names(t, 'ana'), [
      'Send',
      'Status update',
      'Complete',
      'Return',
      'Drop',
    ]);
  });

  test('with no assignee it is with the person who raised it', () {
    final t = ticket(values: {'state': 'Open'});
    expect(names(t, 'rhea'), contains('Send'));
    expect(names(t, 'ana'), isEmpty);
  });

  test('the raiser: Close, only from Completed', () {
    final done = ticket(values: {'assignee': 'ana', 'state': 'Completed'});
    expect(names(done, 'rhea'), ['Close']);
    final open = ticket(values: {'assignee': 'ana', 'state': 'Open'});
    expect(names(open, 'rhea'), isEmpty);
  });

  test('the assignee after Completed: only Return', () {
    final t = ticket(values: {'assignee': 'ana', 'state': 'Completed'});
    expect(names(t, 'ana'), ['Return']);
  });

  test('an admin gets admin actions only once known', () {
    final t = ticket(values: {'assignee': 'ana', 'state': 'Open'});
    expect(names(t, 'zed'), isEmpty);
    expect(names(t, 'zed', isAdmin: true), [
      'Send',
      'Status update',
      'Complete',
      'Return',
      'Drop',
    ]);
  });

  test('a final status offers nothing', () {
    final t = ticket(values: {'assignee': 'ana', 'state': 'Closed'});
    expect(names(t, 'ana', isAdmin: true), isEmpty);
    expect(names(t, 'rhea'), isEmpty);
  });

  test('a status not in `from` hides the action', () {
    final t = ticket(values: {'assignee': 'ana', 'state': 'Returned'});
    expect(names(t, 'ana'), isNot(contains('Close')));
    expect(names(t, 'ana'), contains('Send'));
  });

  test('an unknown status is not final', () {
    final t = ticket(values: {'assignee': 'ana', 'state': 'Weird'});
    expect(t.isFinal, isFalse);
    expect(names(t, 'ana'), isEmpty);
  });

  test('empty `from` means any status that is not final', () {
    const table = TicketTable(
      field: 's',
      statuses: [TicketStatus('A'), TicketStatus('Z', isFinal: true)],
      actions: [
        TicketAction(name: 'Any', who: ['raiser']),
      ],
    );
    const form = TicketForm(key: 'k', caption: 'K', table: table);
    const open = Ticket(
      id: 1,
      by: 'me',
      ts: 0,
      tstruct: 'k',
      values: {'s': 'A'},
      form: form,
    );
    expect(names(open, 'me'), ['Any']);
    expect(names(open.copyWith(values: {'s': 'Z'}), 'me'), isEmpty);
  });

  test('waiting for approval offers no action', () {
    final t = ticket(values: {'assignee': 'ana'}, recordStatus: 'pending');
    expect(names(t, 'ana', isAdmin: true), isEmpty);
    expect(names(t, 'rhea'), isEmpty);
  });

  group('pool (assumption)', () {
    test('shown when the pool field has a value and the status is in from', () {
      final t = ticket(values: {'state': 'Open', 'support_group': 'IT'});
      expect(names(t, 'zed'), ['Take it']);
    });

    test('hidden when the pool field is empty', () {
      final t = ticket(values: {'state': 'Open'});
      expect(names(t, 'zed'), isEmpty);
    });

    test('hidden when the status is not in from', () {
      final t = ticket(values: {'state': 'Forwarded', 'support_group': 'IT'});
      expect(names(t, 'zed'), isEmpty);
    });

    test('inPool from status.get wins over the guess', () {
      final t = ticket(values: {'state': 'Open', 'support_group': 'IT'});
      expect(names(t, 'zed', inPool: false), isEmpty);
      final none = ticket(values: {'state': 'Open'});
      expect(names(none, 'zed', inPool: true), ['Take it']);
    });
  });

  group('edit', () {
    test('the raiser, in an editable status only', () {
      const table = TicketTable(
        field: 'state',
        statuses: [TicketStatus('Open'), TicketStatus('Busy')],
        editableIn: ['Open'],
      );
      const form = TicketForm(key: 'k', caption: 'K', table: table);
      const open = Ticket(
        id: 1,
        by: 'me',
        ts: 0,
        tstruct: 'k',
        values: {'state': 'Open'},
        form: form,
      );
      expect(TicketActions.canEdit(open, 'me'), isTrue);
      expect(TicketActions.canEdit(open, 'other'), isFalse);
      expect(
        TicketActions.canEdit(open.copyWith(values: {'state': 'Busy'}), 'me'),
        isFalse,
      );
      expect(
        TicketActions.canEdit(open.copyWith(recordStatus: 'pending'), 'me'),
        isFalse,
      );
    });

    test(
      'a status missing from a ticket with the first status is editable',
      () {
        final t = ticket(values: {});
        expect(TicketActions.canEdit(t, 'rhea'), isFalse);
      },
    );
  });
}
