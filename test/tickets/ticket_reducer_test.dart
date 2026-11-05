import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/features/tickets/models/ticket_reducer.dart';
import 'package:connectum/features/tickets/models/ticket_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ticket_fixtures.dart';

final _forms = TicketForm.parseAll(
  fixtureData('status_mine_with')['structures'],
);

Ticket t(
  int id, {
  String by = 'rhea',
  String assignee = 'ana',
  String state = 'Open',
  String recordStatus = '',
}) => Ticket(
  id: id,
  by: by,
  ts: 1,
  tstruct: 'help_ticket',
  values: {'assignee': assignee, 'state': state},
  recordStatus: recordStatus,
  form: _forms['help_ticket'],
);

List<int> ids(List<Ticket> l) => [for (final x in l) x.id];

void main() {
  group('refreshed', () {
    test('the page replaces the rows and names the ones that left', () {
      final r = TicketReducer.refreshed([t(1), t(3)], [t(1), t(2), t(3)]);
      expect(ids(r.next), [1, 3]);
      expect(ids(r.gone), [2]);
    });

    test('nothing leaves when the page lists them all', () {
      final r = TicketReducer.refreshed([t(2), t(1)], [t(1), t(2)]);
      expect(ids(r.next), [2, 1]);
      expect(r.gone, isEmpty);
    });

    test('a new row simply arrives', () {
      final r = TicketReducer.refreshed([t(9), t(1)], [t(1)]);
      expect(ids(r.next), [9, 1]);
      expect(r.gone, isEmpty);
    });
  });

  test('appended skips rows already held (Show more)', () {
    expect(ids(TicketReducer.appended([t(1), t(2)], [t(2), t(3)])), [1, 2, 3]);
  });

  test('remove and replace', () {
    expect(ids(TicketReducer.remove([t(1), t(2)], 1)), [2]);
    final r = TicketReducer.replace([t(1), t(2)], t(2, state: 'Closed'));
    expect(r[1].status, 'Closed');
  });

  group('a ticket leaving the list after my action', () {
    test('sent on: no longer with me', () {
      final after = t(1, assignee: 'ben', state: 'Forwarded');
      final r = TicketReducer.afterUpdate(
        [t(1), t(2)],
        after,
        as: 'with',
        user: 'ana',
      );
      expect(r.isGone, isTrue);
    });

    test('completed in the raised tab stays until it is final', () {
      final after = t(1, by: 'ana', assignee: 'ana', state: 'Completed');
      final r = TicketReducer.afterUpdate(
        [after],
        after,
        as: 'raised',
        user: 'ana',
      );
      expect(r.isGone, isFalse);
    });

    test('dropped (final) leaves both tabs', () {
      final after = t(1, by: 'ana', assignee: 'ana', state: 'Dropped');
      for (final as in ['with', 'raised']) {
        expect(
          TicketReducer.afterUpdate([after], after, as: as, user: 'ana').isGone,
          isTrue,
        );
      }
    });

    test('still with me: replaced in place', () {
      final after = t(1, state: 'In progress');
      final r = TicketReducer.afterUpdate(
        [t(1), t(2)],
        after,
        as: 'with',
        user: 'ana',
      );
      expect(r.isGone, isFalse);
      expect(r.next.first.status, 'In progress');
    });

    test('a ticket not on that tab is left alone', () {
      final r = TicketReducer.afterUpdate(
        [t(2)],
        t(1),
        as: 'with',
        user: 'ana',
      );
      expect(r.isGone, isFalse);
      expect(ids(r.next), [2]);
    });

    test('waiting for approval is never with me', () {
      expect(
        TicketReducer.belongsIn(t(1, recordStatus: 'pending'), 'with', 'ana'),
        isFalse,
      );
      expect(
        TicketReducer.belongsIn(
          t(1, by: 'ana', recordStatus: 'pending'),
          'raised',
          'ana',
        ),
        isTrue,
      );
    });
  });

  group('refresh plan for ticket_assigned', () {
    test('the lists are always read again', () {
      const e = TicketAssigned(id: 5, action: 'Raised');
      final plan = TicketRefreshPlan.of(e, openId: 9);
      expect(plan.lists, isTrue);
      expect(plan.openTicket, isFalse);
    });

    test('the open ticket too when it is the one named', () {
      const e = TicketAssigned(id: 9, action: 'Send');
      expect(TicketRefreshPlan.of(e, openId: 9).openTicket, isTrue);
    });

    test('submissions_changed (no ticket named) reads the open one', () {
      expect(TicketRefreshPlan.of(null, openId: 9).openTicket, isTrue);
    });
  });

  group('text', () {
    test('values read simply and never throw', () {
      expect(TicketText.value(null), '');
      expect(TicketText.value('  x '), 'x');
      expect(TicketText.value(4), '4');
      expect(TicketText.value(4.0), '4');
      expect(TicketText.value(true), 'Yes');
      expect(TicketText.value(['a', '', 'b']), 'a, b');
      expect(TicketText.value({'label': 'L', 'id': 1}), 'L');
      expect(TicketText.value({'k': 'v'}), 'k: v');
      expect(TicketText.value('2026-11-05'), '2026-11-05');
    });

    test('ago', () {
      final now = DateTime(2026, 11, 5, 15);
      int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
      expect(TicketText.ago(ago(const Duration(seconds: 5)), now), 'just now');
      expect(TicketText.ago(ago(const Duration(minutes: 5)), now), '5 min ago');
      expect(TicketText.ago(ago(const Duration(hours: 2)), now), '2 h ago');
      expect(TicketText.ago(ago(const Duration(days: 1)), now), 'Yesterday');
      expect(TicketText.ago(0, now), '');
    });
  });
}
