import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/features/inbox/models/inbox_page.dart';
import 'package:connectum/features/inbox/models/inbox_record_tone.dart';
import 'package:connectum/features/inbox/models/inbox_row.dart';
import 'package:flutter_test/flutter_test.dart';

// Ported from the web's tests/frontend/workItems.test.mjs (workItem part).
const _status = {
  'field': 'state',
  'statuses': ['Open', 'In progress', 'Closed'],
  'final': ['Closed'],
};
final _structures = {
  'help_ticket': {'caption': 'Ticket', 'status': _status},
  'plain': {'caption': 'Plain form'},
};

Map<String, dynamic> sub([Map<String, dynamic> o = const {}]) => {
  'id': 1,
  'tstruct': 'help_ticket',
  'by': 'Rhea',
  'holder': 'ana',
  'ts': 1000,
  'completion': 40,
  'values': {'title': ' Printer jammed ', 'state': 'In progress'},
  ...o,
};

InboxRow? row(Map<String, dynamic> s, [Map<String, dynamic>? structures]) =>
    InboxRow.tryParse(s, InboxForm.parseAll(structures ?? _structures));

void main() {
  group('record to row', () {
    test('holder, status, completion, subject', () {
      final it = row(sub())!;
      expect(it.subject, 'Printer jammed');
      expect(it.form, 'Ticket');
      expect(it.holder, 'ana');
      expect(it.raiser, 'rhea');
      expect(it.state, 'In progress');
      expect(it.pct, 40);
      expect(it.tone, 'live');
      expect(it.isWaiting, isFalse);
      final plain = row(sub({'tstruct': 'plain', 'completion': null}))!;
      expect(plain.state, '');
      expect(plain.pct, isNull);
      expect(plain.form, 'Plain form');
      expect(InboxRow.tryParse(null, {}), isNull);
      expect(row({'tstruct': 'plain'}), isNull, reason: 'no number');
      expect(row(sub({'tstruct': 'unknown'}), {})!.form, 'unknown');
    });

    test('subject: first short text, not the status; else form and number', () {
      String by(Map<String, dynamic> values, [int id = 7]) =>
          row(sub({'id': id, 'values': values}))!.subject;
      expect(by({'state': 'Open'}), 'Ticket #7');
      expect(by({'title': '   ', 'state': 'Open'}, 8), 'Ticket #8');
      expect(by({'title': 42}, 9), 'Ticket #9');
      expect(by({'long': 'x' * 121, 'name': 'Short'}, 10), 'Short');
      expect(
        by({'assignee': 'ravi', 'reporter': 'sana', 'title': 'Tag Arun 3'}),
        'Tag Arun 3',
        reason: 'the title, not the first person',
      );
      expect(by({'assignee': 'ravi', 'Name': 'Budget'}), 'Budget');
      expect(by({'assignee': 'ravi', 'reason': 'Family'}), 'ravi');
      expect(by({'title': 'x' * 200, 'reason': 'Short'}), 'Short');
      expect(by({}), 'Ticket #7');
      expect(by({'state': 'Open', 'title': 'T'}), 'T');
      expect(
        by({'state_comments': 'said so', 'send_remarks': 'r', 'a': 'First'}),
        'First',
        reason: 'what a status or a send keeps is never the name',
      );
    });

    test('the holder falls back to the raiser; waiting for approval', () {
      final it = row(sub({'holder': null, 'status': 'pending'}))!;
      expect(it.holder, 'rhea');
      expect(it.isWaiting, isTrue);
      expect(
        row(
          sub({
            'values': {'title': 'x', 'state': 'Closed'},
          }),
        )!.tone,
        'done',
        reason: 'a final status is quiet',
      );
      expect(
        row(
          sub({
            'values': {'title': 'x', 'state': 'Closed'},
          }),
        )!.isFinal,
        isTrue,
      );
    });

    test('a record shared with several people is with all of them', () {
      final it = row({
        'id': 5,
        'tstruct': 't',
        'by': 'rhea',
        'holder': 'rhea',
        'claimants': ['Ana', 'Ben'],
        'values': {},
      }, {})!;
      expect(it.holder, 'ana, @ben');
      expect(
        row({
          'id': 6,
          'tstruct': 't',
          'by': 'rhea',
          'holder': 'sam',
        }, {})!.holder,
        'sam',
      );
    });

    test('team fields, labels, actedBy and externalId are kept', () {
      final it = row(
        sub({
          'team': {
            'via': ['holder', 'sent'],
            'members': ['Maya'],
            'links': {
              'sentTo': ['maya'],
            },
          },
          'labels': {'state': 'In progress'},
          'actedBy': 'Ravi',
          'externalId': 'EXT-1',
        }),
      )!;
      expect(it.via, ['holder', 'sent']);
      expect(it.members, ['maya']);
      expect(it.links, {
        'sentTo': ['maya'],
      });
      expect(it.labels['state'], 'In progress');
      expect(it.actedBy, 'ravi');
      expect(it.externalId, 'EXT-1');
    });

    test('a tolerant parse: wrong shapes are nothing, never a throw', () {
      final it = row(
        sub({
          'team': 'x',
          'labels': [1],
          'values': 'no',
          'claimants': 'no',
          'completion': 'many',
        }),
      )!;
      expect(it.via, isEmpty);
      expect(it.links, isNull);
      expect(it.values, isEmpty);
      expect(it.pct, isNull);
      expect(it.holder, 'ana');
    });
  });

  group('status chip', () {
    test(
      'the live status first, else "Waiting for approval", else the row',
      () {
        final waiting = row(sub({'status': 'pending'}))!;
        expect(waiting.badge, 'Waiting for approval');
        expect(waiting.chipText(null), 'Waiting for approval');
        expect(waiting.chipText(''), 'Waiting for approval');
        expect(waiting.chipText('  '), 'Waiting for approval');
        expect(waiting.chipText('In review'), 'In review');
        final own = row(sub())!;
        expect(own.chipText(null), 'In progress');
        expect(own.chipText('Done'), 'Done');
      },
    );

    test('a record with no status of its own says the approval answer', () {
      final approved = row(
        sub({'tstruct': 'plain', 'status': 'approved', 'values': {}}),
      )!;
      expect(approved.badge, 'Approved');
      final rejected = row(
        sub({'tstruct': 'plain', 'status': 'rejected', 'values': {}}),
      )!;
      expect(rejected.badge, 'Rejected');
      expect(row(sub({'tstruct': 'plain', 'values': {}}))!.chipText(null), '');
    });
  });

  group('the person on the card', () {
    test('holder first, else the raiser; the first of a shared list', () {
      expect(row(sub())!.who, 'ana');
      expect(row(sub({'holder': null}))!.who, 'rhea');
      expect(
        row(
          sub({
            'claimants': ['Ben', 'Ana'],
          }),
        )!.who,
        'ben',
      );
    });

    test('"You" when it is the person looking', () {
      final it = row(sub())!;
      expect(it.isAbout('ANA'), isTrue);
      expect(it.isAbout('rhea'), isFalse);
      expect(it.isAbout(''), isFalse);
      expect(it.whoLabel('ana', cardName: 'Ana Rao'), 'You');
      expect(it.whoLabel('rhea', cardName: 'Ana Rao'), 'Ana Rao');
      expect(it.whoLabel('rhea'), 'ana');
      expect(it.whoLabel('rhea', cardName: '  '), 'ana');
    });
  });

  group('the state of a card', () {
    test('an approved record with no status is completed', () {
      final it = row(
        sub({'tstruct': 'plain', 'status': 'approved', 'values': {}}),
      )!;
      expect(it.stateFor('x'), InboxState.completed);
    });

    test('rejected, waiting, pending, assigned, final', () {
      expect(
        row(sub({'status': 'rejected'}))!.stateFor('ana'),
        InboxState.rejected,
      );
      expect(
        row(sub({'status': 'pending'}))!.stateFor('ana'),
        InboxState.waiting,
      );
      expect(row(sub())!.stateFor('ana'), InboxState.pending);
      expect(row(sub())!.stateFor('olivia'), InboxState.assigned);
      expect(
        row(
          sub({
            'team': {
              'via': ['holder'],
            },
          }),
        )!.stateFor('olivia'),
        InboxState.pending,
      );
      expect(
        row(
          sub({
            'values': {'state': 'Closed'},
          }),
        )!.stateFor('ana'),
        InboxState.completed,
      );
      expect(
        row(
          sub({
            'values': {'state': 'Blocked'},
          }),
        )!.stateFor('ana'),
        InboxState.rejected,
      );
    });

    test('priority is read from the record', () {
      final it = row(
        sub({
          'values': {'title': 'x', 'priority': 'High'},
        }),
      )!;
      expect(it.priority, InboxPriority.high);
      expect(row(sub())!.priority, isNull);
    });
  });

  group('one parser for records.mine and records.query', () {
    test('the same reply gives the same records', () {
      final data = {
        'submissions': [
          sub(),
          sub({'id': 2, 'tstruct': 'plain'}),
        ],
        'structures': _structures,
        'total': 150,
        'hasMore': true,
      };
      final page = InboxPage.parse(data);
      final mine = TicketPage.parse(data);
      expect(page.rows.map((r) => r.id), mine.tickets.map((t) => t.id));
      expect(page.rows.map((r) => r.holder), mine.tickets.map((t) => t.holder));
      expect(page.total, mine.total);
      expect(page.hasMore, mine.hasMore);
      expect(page.received, mine.received);
    });

    test('total falls back to the rows; capped and the id rule', () {
      final page = InboxPage.parse({
        'submissions': [
          sub(),
          {'tstruct': 'x'},
        ],
        'structures': _structures,
        'capped': true,
      });
      expect(page.rows.length, 1);
      expect(page.received, 2);
      expect(page.total, 1);
      expect(page.isCapped, isTrue);
      expect(page.hasMore, isFalse);
      expect(InboxPage.parse({}).rows, isEmpty);
    });

    test('append lists a record once', () {
      final a = InboxPage.parse({
        'submissions': [
          sub(),
          sub({'id': 2}),
        ],
        'structures': _structures,
        'hasMore': true,
        'total': 5,
      });
      final b = InboxPage.parse({
        'submissions': [
          sub({'id': 2}),
          sub({'id': 3}),
        ],
        'structures': _structures,
        'total': 5,
      });
      final all = a.append(b);
      expect(all.rows.map((r) => r.id), [1, 2, 3]);
      expect(all.hasMore, isFalse);
      expect(all.received, 4);
    });
  });

  group('counts, people, cards', () {
    test('counts need me, team and all as numbers', () {
      final c = InboxCounts.tryParse({
        'me': 3,
        'team': 4,
        'all': 1001,
        'reports': 2,
        'cap': 1000,
      })!;
      expect(c.label(c.all), '1000+');
      expect(c.label(c.me), '3');
      expect(c.reports, 2);
      expect(InboxCounts.tryParse({'me': 1, 'team': 2}), isNull);
      expect(InboxCounts.tryParse({'me': '1', 'team': 2, 'all': 3}), isNull);
      expect(InboxCounts.tryParse(null), isNull);
      expect(InboxCounts.tryParse({'me': 1, 'team': 2, 'all': 3})!.cap, 1000);
    });

    test('people lists keep only names', () {
      final p = InboxPeople.parse({
        'team': ['a', 3, 'b'],
        'sentBy': 'x',
      });
      expect(p.team, ['a', 'b']);
      expect(p.sentBy, isEmpty);
      expect(p.sentTo, isEmpty);
    });
  });
}
