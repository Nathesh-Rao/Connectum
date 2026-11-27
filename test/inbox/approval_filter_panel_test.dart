import 'package:connectum/data/models/approval.dart';
import 'package:connectum/features/inbox/inbox_controller.dart';
import 'package:connectum/features/inbox/models/approval_entries.dart';
import 'package:connectum/features/inbox/models/approval_panel.dart';
import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';
import 'inbox_support.dart';

int ts(int y, int m, int d) => DateTime(y, m, d, 12).millisecondsSinceEpoch;

Map<String, dynamic> req(
  int id, {
  String status = 'pending',
  String direction = 'incoming',
  bool canRespond = false,
  String from = 'rhea',
  String form = 'leave',
  String caption = 'Leave request',
  List<String> approvers = const ['ana'],
  String? resolvedBy,
  required int createdTs,
  List<(String, String)> summary = const [],
  bool team = false,
}) => {
  'id': id,
  'type': 'submission',
  'status': status,
  'from': from,
  'fromUser': from,
  'fromName': from,
  'approvers': approvers,
  'direction': direction,
  'canRespond': canRespond,
  'createdTs': createdTs,
  'resolvedBy': ?resolvedBy,
  'tstruct': form,
  if (team) 'team': true,
  'data': {
    'caption': caption,
    'summary': [
      for (final (c, v) in summary) {'caption': c, 'value': v},
    ],
  },
};

Map<String, dynamic> page(List<Map<String, dynamic>> rows) => {
  'requests': rows,
  'total': rows.length,
  'hasMore': false,
};

/// The person is `ana`. Newest first: 2, 1, 3, 4.
final own = [
  req(
    1,
    canRespond: true,
    createdTs: ts(2026, 3, 3),
    summary: [
      ('Days', '3'),
      ('Start', '2026-03-10'),
      ('Reason', 'Wedding trip'),
    ],
  ),
  req(
    2,
    direction: 'outgoing',
    from: 'ana',
    approvers: ['bob'],
    createdTs: ts(2026, 3, 20),
    summary: [('Days', '10'), ('Start', '2026-04-15'), ('Reason', 'Holiday')],
  ),
  req(
    3,
    status: 'accepted',
    from: 'sam',
    form: 'expense',
    caption: 'Expense claim',
    resolvedBy: 'ana',
    createdTs: ts(2026, 2, 10),
    summary: [
      ('Amount', '250.5'),
      ('Spent on', '09/02/2026'),
      ('Note', 'Taxi'),
    ],
  ),
  req(
    4,
    status: 'rejected',
    direction: 'outgoing',
    from: 'ana',
    form: 'expense',
    caption: 'Expense claim',
    approvers: ['bob', 'ana'],
    resolvedBy: 'bob',
    createdTs: ts(2026, 1, 5),
    summary: [('Amount', '40'), ('Spent on', '2026-01-04'), ('Note', 'Lunch')],
  ),
];

final team = [
  req(
    5,
    from: 'tim',
    direction: 'other',
    createdTs: ts(2026, 3, 1),
    team: true,
  ),
  req(6, from: 'tim', canRespond: true, createdTs: ts(2026, 3, 2), team: true),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;

  InboxController start({int reports = 0}) {
    rig = InboxRig();
    addTearDown(rig.dispose);
    rig.routes['records.query'] = (_) => queryReply([record(1)]);
    rig.routes['records.counts'] = (_) => countsReply(reports: reports);
    rig.routes['req.list'] = (_) => page(own);
    rig.routes['req.team'] = (_) => page(team);
    rig.controller.onInit();
    return rig.controller;
  }

  List<int> idsOf(InboxController c) => [
    for (final r in c.approvals.rows) r.id,
  ];

  Future<InboxController> read({int reports = 0}) async {
    final c = start(reports: reports);
    await settle();
    return c;
  }

  Future<void> applying(InboxController c, ApprovalPanel p) async {
    c.approvals.applyPanel(p);
    await settle();
  }

  InboxBlock block(String form, List<InboxCondition> conds) =>
      InboxBlock(forms: [form], conditions: conds);

  InboxCondition cond(
    String field,
    String op,
    String value, {
    String value2 = '',
    String join = 'and',
  }) => InboxCondition(
    field: field,
    op: op,
    value: value,
    value2: value2,
    join: join,
  );

  group('nothing is ticked until the person ticks it', () {
    test(
      'the panel starts empty and a chip or the toggle sets nothing',
      () async {
        final c = await read(reports: 1);
        final a = c.approvals;
        expect(a.panel.value.entries, isEmpty);
        expect(a.panelCount, 0);
        a.pickPrimary(ApprovalPrimary.pending);
        a.pickSide(ApprovalSide.team);
        a.pickPrimary(ApprovalPrimary.rejected);
        a.pickSide(ApprovalSide.me);
        expect(a.panel.value.entries, isEmpty);
        expect(a.panelCount, 0);
      },
    );

    test('the grey hint is what the toggle shows, per chip and side', () {
      String hint(ApprovalPrimary p, ApprovalSide s) =>
          ApprovalPanelRules.usualText(p, s, hasTeam: true);
      expect(
        hint(ApprovalPrimary.pending, ApprovalSide.me),
        'Pending by me, Pending with me',
      );
      expect(
        hint(ApprovalPrimary.pending, ApprovalSide.team),
        'Pending to team',
      );
      expect(
        hint(ApprovalPrimary.approved, ApprovalSide.me),
        'Approved by me, Approved for me',
      );
      expect(
        hint(ApprovalPrimary.requests, ApprovalSide.me),
        'Sent to me, Sent by me',
      );
      expect(hint(ApprovalPrimary.requests, ApprovalSide.team), 'Sent by team');
      expect(
        hint(ApprovalPrimary.rejected, ApprovalSide.me),
        'Rejected by me, Rejected for me',
      );
      expect(
        hint(ApprovalPrimary.all, ApprovalSide.team).split(', '),
        hasLength(4),
      );
      expect(
        hint(ApprovalPrimary.all, ApprovalSide.me).split(', '),
        hasLength(8),
      );
      // Without reports the team is never the side.
      expect(
        ApprovalPanelRules.usualText(
          ApprovalPrimary.pending,
          ApprovalSide.team,
          hasTeam: false,
        ),
        'Pending by me, Pending with me',
      );
    });

    test('a chip offers its entries, the team ones only with reports', () {
      expect(ApprovalPanelRules.offered(ApprovalPrimary.pending, true), [
        ApprovalEntry.pendingByMe,
        ApprovalEntry.pendingWithMe,
        ApprovalEntry.pendingToTeam,
      ]);
      expect(ApprovalPanelRules.offered(ApprovalPrimary.pending, false), [
        ApprovalEntry.pendingByMe,
        ApprovalEntry.pendingWithMe,
      ]);
    });
  });

  group('the badge counts only what the person changed', () {
    test('tick shows 1, taking the tick away shows nothing', () async {
      final c = await read();
      final a = c.approvals;
      final p = a.newPanel()..onInit();
      p.toggleEntry(ApprovalEntry.pendingWithMe);
      expect(p.count, 1);
      p.toggleEntry(ApprovalEntry.pendingByMe);
      expect(p.count, 1, reason: 'the entries are one line');
      p.toggleEntry(ApprovalEntry.pendingWithMe);
      p.toggleEntry(ApprovalEntry.pendingByMe);
      expect(p.count, 0);
      p.apply();
      expect(a.panelCount, 0);
      p.onClose();
    });

    test('every line counts once', () {
      expect(
        ApprovalPanel(
          entries: [ApprovalEntry.sentByMe],
          forms: ['leave'],
          raisedBy: ['ana'],
          approvers: ['bob'],
          from: '2026-01-01',
          to: '2026-02-01',
          sort: InboxSort.oldest,
          blocks: [
            block('leave', [cond('Days', 'gt', '1')]),
          ],
        ).count,
        7,
      );
      expect(ApprovalPanel.none.count, 0);
    });
  });

  group('the toggle follows the ticks', () {
    test('one side follows, a mixed choice lights neither side', () async {
      final c = await read(reports: 1);
      final a = c.approvals..pickPrimary(ApprovalPrimary.pending);
      expect(a.shownSide, ApprovalSide.me);
      await applying(c, ApprovalPanel(entries: [ApprovalEntry.pendingToTeam]));
      expect(a.side.value, ApprovalSide.team);
      expect(a.shownSide, ApprovalSide.team);
      await applying(
        c,
        ApprovalPanel(
          entries: [ApprovalEntry.pendingByMe, ApprovalEntry.pendingWithMe],
        ),
      );
      expect(a.side.value, ApprovalSide.me);
      expect(a.shownSide, ApprovalSide.me);
      await applying(
        c,
        ApprovalPanel(
          entries: [ApprovalEntry.pendingByMe, ApprovalEntry.pendingToTeam],
        ),
      );
      expect(a.shownSide, isNull);
      // The list is the union of the ticked entries.
      expect(idsOf(c).toSet(), {2, 6});
    });

    test('an entry the chip does not have is dropped on Apply', () async {
      final c = await read(reports: 1);
      final a = c.approvals..pickPrimary(ApprovalPrimary.pending);
      await applying(c, ApprovalPanel(entries: [ApprovalEntry.approvedByMe]));
      expect(a.panel.value.entries, isEmpty);
      expect(a.panelCount, 0);
    });

    test('ticks cut the chip: only the ticked entries are listed', () async {
      final c = await read();
      final a = c.approvals..pickPrimary(ApprovalPrimary.pending);
      expect(idsOf(c).toSet(), {1, 2});
      await applying(c, ApprovalPanel(entries: [ApprovalEntry.pendingByMe]));
      expect(idsOf(c), [2]);
      await applying(c, ApprovalPanel(entries: [ApprovalEntry.pendingWithMe]));
      expect(idsOf(c), [1]);
      // The chip's number is the cut too.
      expect(a.primaryCounts[ApprovalPrimary.pending], 1);
      // Another chip counts its own toggle side, no ticks.
      expect(a.primaryCounts[ApprovalPrimary.all], 4);
    });
  });

  group('each line cuts the requests', () {
    test('all four by default, newest first', () async {
      final c = await read();
      expect(idsOf(c), [2, 1, 3, 4]);
    });

    test('Data', () async {
      final c = await read();
      await applying(c, ApprovalPanel(forms: ['expense']));
      expect(idsOf(c), [3, 4]);
      await applying(c, ApprovalPanel(forms: ['expense', 'leave']));
      expect(idsOf(c), [2, 1, 3, 4]);
    });

    test(
      'Data chips count under the other lines, never offer a form with none',
      () async {
        final c = await read();
        final p = c.approvals.newPanel()..onInit();
        expect(
          [for (final f in p.formChoices) f.label],
          ['Expense claim (2)', 'Leave request (2)'],
        );
        p.setRaisedBy(['ana']);
        expect(
          [for (final f in p.formChoices) f.label],
          ['Expense claim (1)', 'Leave request (1)'],
        );
        p.setRaisedBy(['sam']);
        expect([for (final f in p.formChoices) f.label], ['Expense claim (1)']);
        p.onClose();
      },
    );

    test('Raised by', () async {
      final c = await read();
      await applying(c, ApprovalPanel(raisedBy: ['ana']));
      expect(idsOf(c), [2, 4]);
      await applying(c, ApprovalPanel(raisedBy: ['rhea', 'sam']));
      expect(idsOf(c), [1, 3]);
    });

    test('Approver', () async {
      final c = await read();
      await applying(c, ApprovalPanel(approvers: ['bob']));
      expect(idsOf(c), [2, 4]);
      await applying(c, ApprovalPanel(approvers: ['ana']));
      expect(idsOf(c), [1, 3, 4]);
    });

    test('people lines offer only people on the loaded requests', () async {
      final c = await read();
      final p = c.approvals.newPanel()..onInit();
      expect(p.peopleOf(false).toSet(), {'rhea', 'ana', 'sam'});
      expect(p.peopleOf(true).toSet(), {'ana', 'bob'});
      p.onClose();
    });

    test('Date from and to are inclusive, either end may be open', () async {
      final c = await read();
      await applying(c, ApprovalPanel(from: '2026-03-01'));
      expect(idsOf(c), [2, 1]);
      await applying(c, ApprovalPanel(to: '2026-02-10'));
      expect(idsOf(c), [3, 4]);
      await applying(c, ApprovalPanel(from: '2026-02-01', to: '2026-03-03'));
      expect(idsOf(c), [1, 3]);
    });

    test('Sort', () async {
      final c = await read();
      await applying(c, ApprovalPanel(sort: InboxSort.oldest));
      expect(idsOf(c), [4, 3, 1, 2]);
      await applying(c, ApprovalPanel(sort: InboxSort.asc));
      expect(idsOf(c), [3, 4, 2, 1], reason: 'by title, newest first on a tie');
      await applying(c, ApprovalPanel(sort: InboxSort.desc));
      expect(idsOf(c), [2, 1, 3, 4]);
      await applying(c, ApprovalPanel(sort: InboxSort.latest));
      expect(idsOf(c), [2, 1, 3, 4]);
    });

    test('Advanced, text conditions with and / or', () async {
      final c = await read();
      await applying(
        c,
        ApprovalPanel(
          blocks: [
            block('leave', [cond('Reason', 'contains', 'wedding')]),
          ],
        ),
      );
      expect(idsOf(c), [1]);
      await applying(
        c,
        ApprovalPanel(
          blocks: [
            block('leave', [
              cond('Reason', 'contains', 'wedding'),
              cond('Reason', 'eq', 'holiday', join: 'or'),
            ]),
          ],
        ),
      );
      expect(idsOf(c), [2, 1]);
      await applying(
        c,
        ApprovalPanel(
          blocks: [
            block('leave', [
              cond('Reason', 'contains', 'wedding'),
              cond('Reason', 'eq', 'holiday'),
            ]),
          ],
        ),
      );
      expect(idsOf(c), isEmpty);
      await applying(
        c,
        ApprovalPanel(
          blocks: [
            block('expense', [cond('Note', 'starts', 'ta')]),
          ],
        ),
      );
      expect(idsOf(c), [3]);
      await applying(
        c,
        ApprovalPanel(
          blocks: [
            block('expense', [cond('Note', 'notempty', '')]),
          ],
        ),
      );
      expect(idsOf(c), [3, 4]);
    });

    test('Advanced, number conditions', () async {
      final c = await read();
      Future<void> only(InboxCondition k) => applying(
        c,
        ApprovalPanel(
          blocks: [
            block('expense', [k]),
          ],
        ),
      );
      await only(cond('Amount', 'gt', '100'));
      expect(idsOf(c), [3]);
      await only(cond('Amount', 'between', '30', value2: '50'));
      expect(idsOf(c), [4]);
      await only(cond('Amount', 'eq', '250.5'));
      expect(idsOf(c), [3]);
      await only(cond('Amount', 'lte', '40'));
      expect(idsOf(c), [4]);
      await only(cond('Amount', 'ne', '40'));
      expect(idsOf(c), [3]);
      await applying(
        c,
        ApprovalPanel(
          blocks: [
            block('leave', [cond('Days', 'gte', '10')]),
          ],
        ),
      );
      expect(idsOf(c), [2], reason: '10 is a number, not text, so 3 < 10');
    });

    test(
      'Advanced, date conditions, whatever way the card writes the day',
      () async {
        final c = await read();
        Future<void> only(InboxCondition k) => applying(
          c,
          ApprovalPanel(
            blocks: [
              block('expense', [k]),
            ],
          ),
        );
        await only(cond('Spent on', 'lt', '2026-02-01'));
        expect(idsOf(c), [4]);
        await only(
          cond('Spent on', 'between', '2026-02-01', value2: '2026-02-28'),
        );
        expect(idsOf(c), [3], reason: '09/02/2026 is 9 February');
        await only(cond('Spent on', 'eq', '2026-02-09'));
        expect(idsOf(c), [3]);
        await only(cond('Spent on', 'gte', '2026-01-04'));
        expect(idsOf(c), [3, 4]);
        await applying(
          c,
          ApprovalPanel(
            blocks: [
              block('leave', [cond('Start', 'after', '2026-04-01')]),
            ],
          ),
        );
        expect(
          idsOf(c),
          isEmpty,
          reason: 'an operator that is not known never passes',
        );
        await applying(
          c,
          ApprovalPanel(
            blocks: [
              block('leave', [cond('Start', 'gt', '2026-04-01')]),
            ],
          ),
        );
        expect(idsOf(c), [2]);
      },
    );

    test(
      'Advanced, a value of the wrong kind never passes, empty is a test',
      () async {
        expect(
          ApprovalPanelRules.conditionHolds(
            'abc',
            cond('A', 'gt', '1'),
            'number',
          ),
          isFalse,
        );
        expect(
          ApprovalPanelRules.conditionHolds(
            'abc',
            cond('A', 'gt', '2026-01-01'),
            'date',
          ),
          isFalse,
        );
        expect(
          ApprovalPanelRules.conditionHolds('', cond('A', 'empty', ''), 'text'),
          isTrue,
        );
        expect(
          ApprovalPanelRules.conditionHolds('', cond('A', 'eq', 'x'), 'text'),
          isFalse,
        );
        expect(
          ApprovalPanelRules.conditionHolds(
            '1,200',
            cond('A', 'gt', '1000'),
            'number',
          ),
          isTrue,
        );
      },
    );

    test('Advanced, blocks: any holds; conditions only for one form', () async {
      final c = await read();
      await applying(
        c,
        ApprovalPanel(
          blocks: [
            block('leave', [cond('Reason', 'contains', 'wedding')]),
            block('expense', [cond('Amount', 'gt', '100')]),
          ],
        ),
      );
      expect(idsOf(c).toSet(), {1, 3});
      await applying(
        c,
        ApprovalPanel(
          blocks: [
            InboxBlock(
              forms: ['leave', 'expense'],
              conditions: [cond('Reason', 'contains', 'zzz')],
            ),
          ],
        ),
      );
      expect(idsOf(c).toSet(), {1, 2, 3, 4}, reason: 'forms only');
      // A block that says nothing is dropped.
      await applying(c, ApprovalPanel(blocks: [InboxBlock()]));
      expect(idsOf(c), [2, 1, 3, 4]);
    });

    test(
      'fields are the captions the cards carry, the kind from their values',
      () async {
        final c = await read();
        final fields = ApprovalPanelRules.fieldsOf(c.approvals.pool, 'leave');
        expect(
          {for (final f in fields) f.caption: f.kind},
          {'Days': 'number', 'Start': 'date', 'Reason': 'text'},
        );
        final exp = ApprovalPanelRules.fieldsOf(c.approvals.pool, 'expense');
        expect(
          {for (final f in exp) f.caption: f.kind},
          {'Amount': 'number', 'Spent on': 'date', 'Note': 'text'},
        );
        expect(ApprovalPanelRules.kindOfValues(['', '']), 'text');
        expect(ApprovalPanelRules.kindOfValues(['3', 'x']), 'text');
        expect(ApprovalPanelRules.kindOfValues(['3', '', '4.5']), 'number');
      },
    );

    test('at most eight summary fields of a card are read', () {
      final a = Approval.tryParse(
        req(
          9,
          createdTs: 1,
          summary: [for (var i = 1; i <= 10; i++) ('F$i', '$i')],
        ),
      )!;
      expect(ApprovalPanelRules.fieldsOf([a], 'leave').map((f) => f.caption), [
        for (var i = 1; i <= 8; i++) 'F$i',
      ]);
    });

    test('the panel controller builds a condition from a field', () async {
      final c = await read();
      final p = c.approvals.newPanel()..onInit();
      p.toggleAdvanced();
      final b = p.draft.value.blocks.single;
      p.setBlockForms(b.id, ['expense']);
      p.addCondition(b.id);
      var now = p.draft.value.blocks.single;
      p.setConditionField(b.id, now.conditions.single.id, 'Amount');
      now = p.draft.value.blocks.single;
      expect(now.conditions.single.op, 'eq', reason: 'a number starts on =');
      expect([
        for (final o in p.operatorChoices(now, now.conditions.single)) o.id,
      ], contains('between'));
      p.setConditionField(b.id, now.conditions.single.id, 'Note');
      now = p.draft.value.blocks.single;
      expect(now.conditions.single.op, 'contains');
      // Another form drops the conditions.
      p.setBlockForms(b.id, ['leave']);
      expect(p.draft.value.blocks.single.conditions, isEmpty);
      p.onClose();
    });
  });

  group('the state is kept, and never saved in a view', () {
    test(
      'it stays across tabs and chips; a chip drops only the ticks',
      () async {
        final c = await read(reports: 1);
        final a = c.approvals;
        await applying(
          c,
          ApprovalPanel(
            entries: [ApprovalEntry.sentByMe],
            forms: ['leave'],
            sort: InboxSort.oldest,
          ),
        );
        c.closeApprovals();
        c.openApprovals();
        expect(a.panel.value.forms, ['leave']);
        expect(a.panel.value.entries, [ApprovalEntry.sentByMe]);
        a.pickPrimary(ApprovalPrimary.pending);
        expect(a.panel.value.entries, isEmpty);
        expect(a.panel.value.forms, ['leave']);
        expect(a.panel.value.sort, InboxSort.oldest);
        expect(a.panelCount, 2);
        a.pickSide(ApprovalSide.team);
        expect(a.panel.value.forms, ['leave']);
      },
    );

    test(
      'the panel never reaches the Records filter or a saved view',
      () async {
        final c = await read();
        final before = c.filter.value.toSetup();
        await applying(
          c,
          ApprovalPanel(
            entries: [ApprovalEntry.sentByMe],
            forms: ['leave'],
            raisedBy: ['ana'],
            sort: InboxSort.asc,
            blocks: [
              block('leave', [cond('Days', 'gt', '1')]),
            ],
          ),
        );
        expect(c.approvals.panelCount, 5);
        expect(c.filter.value.toSetup(), before);
        expect(c.filterCount, 0);
        expect(c.filter.value.forms, isEmpty);
      },
    );

    test(
      'Clear empties the lines, a new session or link starts clean',
      () async {
        final c = await read();
        await applying(c, ApprovalPanel(forms: ['leave']));
        final p = c.approvals.newPanel()..onInit();
        p.clear();
        p.onClose();
        expect(c.approvals.panel.value.isEmpty, isTrue);
        await applying(c, ApprovalPanel(forms: ['leave']));
        c.approvals.clearFilters();
        expect(c.approvals.panelCount, 0);
      },
    );
  });
}
