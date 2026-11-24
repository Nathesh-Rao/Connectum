import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/data/models/approval.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/inbox/inbox_controller.dart';
import 'package:connectum/features/inbox/inbox_filter_controller.dart';
import 'package:connectum/features/inbox/models/inbox_approval_rows.dart';
import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:connectum/features/inbox/models/inbox_saved_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';
import 'inbox_support.dart';

final now = DateTime(2026, 11, 24, 12);
int daysAgo(num d) => now.millisecondsSinceEpoch - (d * 86400000).round();

Approval ap(
  int id, {
  String status = Approval.pending,
  bool canRespond = true,
  String form = 'leave',
  String caption = 'Leave request',
  int? createdTs,
}) => Approval(
  id: id,
  type: 'submission',
  status: status,
  canRespond: canRespond,
  direction: canRespond ? Approval.incoming : Approval.outgoing,
  from: 'rhea',
  formId: form,
  caption: caption,
  createdTs: createdTs ?? daysAgo(1) - id,
);

Map<String, dynamic> raw(Approval a) => {
  'id': a.id,
  'type': a.type,
  'status': a.status,
  'from': a.from,
  'fromName': 'Rhea',
  'approvers': ['ana'],
  'direction': a.direction,
  'canRespond': a.canRespond,
  'createdTs': a.createdTs,
  'data': {'caption': a.caption, 'tstruct': a.formId},
};

InboxFilter f(
  List<String> wheres, {
  List<String> forms = const [],
  List<String> approvalPick = const [],
  List<String> createdBy = const [],
  String from = '',
  String to = '',
  String sort = 'latest',
  String status = '',
}) => InboxFilter(
  wheres: wheres,
  forms: forms,
  approvalPick: approvalPick,
  createdBy: createdBy,
  from: from,
  to: to,
  sort: sort,
  status: status,
);

List<int> ids(List<Approval> l) => [for (final a in l) a.id];

List<int> cards(InboxFilter filter, List<Approval> all, {String q = ''}) =>
    ids(InboxApprovalRows(filter).cards(all, query: q, now: now));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final all = [
    ap(1), // pending, mine
    ap(2, canRespond: false), // pending, someone else's
    ap(3, status: Approval.accepted, canRespond: false, form: 'expense'),
    ap(4, status: Approval.rejected, canRespond: false),
    ap(5, status: Approval.ignored, canRespond: false), // closed
    ap(6, form: 'expense', caption: 'Expense claim'),
  ];

  group('entry rules', () {
    test('an approval-only choice asks no records; a mixed one does', () {
      expect(f(['approvals']).serverViews(), isEmpty);
      expect(InboxApprovalRows(f(['approvals'])).isApprovalsOnly, isTrue);
      expect(
        InboxApprovalRows(f(['approved', 'rejected'])).isApprovalsOnly,
        isTrue,
      );
      final mixed = f(['me', 'approved']);
      expect(mixed.serverViews(), [
        {
          'scope': ['me'],
        },
      ]);
      expect(InboxApprovalRows(mixed).isApprovalsOnly, isFalse);
    });

    test('Timeline stays exclusive', () {
      expect(InboxWhere.choice(['approvals'], ['approvals', 'timeline']), [
        'timeline',
      ]);
      expect(InboxWhere.choice(['timeline'], ['timeline', 'approved']), [
        'approved',
      ]);
    });

    test('the panel offers the four approval entries', () {
      for (final w in ['allapprovals', 'approvals', 'approved', 'rejected']) {
        expect(InboxWhere.offered, contains(w));
      }
      expect(InboxWhere.stageOf, {
        'allapprovals': 'any',
        'approvals': 'pending',
        'approved': 'approved',
        'rejected': 'rejected',
      });
    });
  });

  group('one approval entry is a list of its own', () {
    test('Pending my approvals: pending and canRespond only', () {
      expect(cards(f(['approvals']), all), [1, 6]);
    });

    test('Approvals holds every answer, closed ones too', () {
      expect(cards(f(['allapprovals']), all), [1, 2, 3, 4, 5, 6]);
    });

    test('Approved and Rejected', () {
      expect(cards(f(['approved']), all), [3]);
      expect(cards(f(['rejected']), all), [4]);
    });

    test('Data cuts by the form (the tstruct)', () {
      expect(cards(f(['allapprovals'], forms: ['expense']), all), [3, 6]);
    });

    test('a form named in an Advanced block cuts the same way', () {
      final filter = f(['allapprovals']).copyWith(
        blocks: [
          InboxBlock(forms: const ['expense']),
        ],
      );
      expect(cards(filter, all), [3, 6]);
    });

    test('the people lines and Open / Closed are the records\' own', () {
      expect(
        cards(f(['allapprovals'], createdBy: ['zed'], status: 'closed'), all),
        [1, 2, 3, 4, 5, 6],
      );
    });

    test('Date cuts by the request time, the last day to its end', () {
      final day = DateTime.fromMillisecondsSinceEpoch(daysAgo(10));
      String iso(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final old = ap(7, createdTs: daysAgo(10));
      final list = [...all, old];
      expect(cards(f(['allapprovals'], to: iso(day)), list), [7]);
      expect(cards(f(['allapprovals'], from: iso(day)), list), [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      ]);
      expect(
        cards(
          f(['allapprovals'], from: iso(now.add(const Duration(days: 1)))),
          list,
        ),
        isEmpty,
      );
    });

    test('Sort: oldest, and A to Z by the title', () {
      final list = [
        ap(1, caption: 'Zebra'),
        ap(2, caption: 'apple'),
        ap(3, caption: 'Mango'),
      ];
      expect(cards(f(['allapprovals']), list), [1, 2, 3]);
      expect(cards(f(['allapprovals'], sort: 'oldest'), list), [3, 2, 1]);
      expect(cards(f(['allapprovals'], sort: 'asc'), list), [2, 3, 1]);
      expect(cards(f(['allapprovals'], sort: 'desc'), list), [1, 3, 2]);
    });

    test('the search narrows the cards', () {
      expect(cards(f(['allapprovals']), all, q: 'expense'), [6]);
    });
  });

  group('several entries: approvals under the records', () {
    test('only the answers of the entries; pending only the person\'s', () {
      expect(cards(f(['me', 'approvals']), all), [1, 6]);
      expect(cards(f(['me', 'approved']), all), [3]);
      expect(cards(f(['approved', 'rejected']), all), [3, 4]);
    });

    test('with Approvals every pending one is listed', () {
      expect(cards(f(['me', 'allapprovals']), all), [1, 2, 3, 4, 5, 6]);
    });

    test('Data applies; Date, Sort and the people lines do not', () {
      final filter = f(
        ['me', 'allapprovals'],
        forms: ['expense'],
        createdBy: ['zed'],
        from: '2030-01-01',
        sort: 'oldest',
        status: 'open',
      );
      expect(cards(filter, all), [3, 6]);
    });

    test('Me / My Team alone is the switch: no approvals', () {
      expect(cards(f(const []), all), isEmpty);
      expect(cards(f(['requests']), all), isEmpty);
    });

    test('Advanced ticks need a named form that has an approval flow', () {
      final noForm = f(const [], approvalPick: ['approved']);
      expect(cards(noForm, all), isEmpty);
      final named = f(const [], forms: ['expense'], approvalPick: ['approved']);
      expect(cards(named, all), [3]);
      final noFlow = f(const [], forms: ['other'], approvalPick: ['approved']);
      expect(cards(noFlow, all), isEmpty);
    });

    test('the Pending tick lists a pending one that is not the person\'s', () {
      final named = f(const [], forms: ['leave'], approvalPick: ['pending']);
      expect(cards(named, all), [1, 2]);
    });
  });

  group('escalations', () {
    final waits = [
      ap(1, createdTs: daysAgo(4)),
      ap(2, createdTs: daysAgo(3) - 1),
      ap(3, createdTs: daysAgo(3)),
      ap(4, createdTs: daysAgo(5), canRespond: false),
      ap(5, createdTs: daysAgo(5), status: Approval.accepted),
    ];

    test('waiting for the person longer than 3 days, boundary exclusive', () {
      expect(cards(f(['escalations']), waits), [2, 1]);
    });

    test('with other entries they sit under the records', () {
      expect(cards(f(['me', 'escalations']), waits), [2, 1]);
    });

    test('an approval already listed is not listed twice', () {
      expect(cards(f(['allapprovals', 'escalations']), waits), [3, 2, 1, 5, 4]);
    });

    test('Data and the search do not cut them (the web draws them whole)', () {
      expect(cards(f(['escalations'], forms: ['expense']), waits, q: 'zzz'), [
        2,
        1,
      ]);
    });
  });

  group('facets', () {
    test('the form counts add up to the cards, whatever form is named', () {
      for (final filter in [
        f(['allapprovals']),
        f(['approvals']),
        f(['me', 'approved']),
        f(['approved', 'rejected']),
        f(['me', 'allapprovals'], forms: ['expense']),
      ]) {
        final plan = InboxApprovalRows(filter);
        final counts = plan.formCounts(all);
        final unnamed = filter.copyWith(forms: const []);
        final total = InboxApprovalRows(unnamed).cards(all, now: now).length;
        expect(
          counts.values.fold<int>(0, (a, b) => a + b),
          total,
          reason: '${filter.wheres}',
        );
      }
    });

    test('no approval entry, no counts', () {
      expect(InboxApprovalRows(f(['me'])).formCounts(all), isEmpty);
    });

    test('counts follow Date in the one-entry list (so they add up)', () {
      final list = [...all, ap(8, createdTs: daysAgo(30))];
      final filter = f(['allapprovals'], from: '2026-11-20');
      final counts = InboxApprovalRows(filter).formCounts(list);
      expect(
        counts.values.fold<int>(0, (a, b) => a + b),
        InboxApprovalRows(filter).cards(list, now: now).length,
      );
    });
  });

  group('the Inbox list', () {
    late InboxRig rig;

    Future<InboxController> start({
      List<Approval>? approvals,
      List<Map<String, dynamic>>? records,
    }) async {
      rig = InboxRig();
      addTearDown(rig.dispose);
      rig.routes['records.query'] = (_) =>
          queryReply(records ?? [record(2), record(1)]);
      rig.routes['req.list'] = (_) => {
        'requests': [for (final a in approvals ?? all) raw(a)],
        'total': (approvals ?? all).length,
        'hasMore': false,
      };
      final c = rig.controller..onInit();
      await settle();
      return c;
    }

    int recordAsks() => rig.asked.where((a) => a == 'records.query').length;

    test(
      'an approval-only choice asks no records and lists approvals',
      () async {
        final c = await start();
        final before = recordAsks();
        c.applyFilter(f(['approved', 'rejected']));
        await settle();
        expect(recordAsks(), before);
        expect(c.isRecordsOff, isTrue);
        expect(c.rows, isEmpty);
        expect(ids(c.approvalCards), [3, 4]);
        expect(c.viewState.value, AppViewState.content);
        expect(c.totalLabel, '2 approvals');
      },
    );

    test(
      'a mixed choice asks the records and draws approvals under them',
      () async {
        final c = await start();
        c.applyFilter(f(['team', 'approved']));
        await settle();
        final ask = rig.argsOf('records.query').last;
        expect(ask['views'], [
          {
            'scope': ['team'],
          },
        ]);
        expect(c.rows, isNotEmpty);
        expect(ids(c.approvalCards), [3]);
        expect(c.totalLabel, '2 records, 1 approval');
      },
    );

    test('Timeline is exclusive and has no approvals', () async {
      final c = await start();
      c.applyFilter(
        f(InboxWhere.choice(['approvals'], ['approvals', 'timeline'])),
      );
      await settle();
      expect(c.filter.value.wheres, ['timeline']);
      expect(c.approvalCards, isEmpty);
      expect(c.hasApprovalsPart, isFalse);
    });

    test(
      'the button count stays pending and canRespond, filter or not',
      () async {
        final c = await start();
        expect(c.approvals.count, 2);
        c.applyFilter(f(['allapprovals']));
        await settle();
        expect(c.approvals.count, 2);
      },
    );

    test('applying a filter closes the Approvals pane', () async {
      final c = await start();
      c.openApprovals();
      c.applyFilter(f(['approved']));
      expect(c.isApprovalsOpen.value, isFalse);
    });

    test(
      'nothing matched in either: the filter text, not a blank list',
      () async {
        final c = await start(approvals: const [], records: const []);
        c.applyFilter(f(['me', 'approved']));
        await settle();
        expect(c.viewState.value, AppViewState.empty);
        expect(c.emptyText, InboxController.noFilterMatchTitle);
      },
    );

    test(
      'records empty but approvals matched: the list, not the empty state',
      () async {
        final c = await start(records: const []);
        c.applyFilter(f(['me', 'approved']));
        await settle();
        expect(c.rows, isEmpty);
        expect(c.viewState.value, AppViewState.content);
      },
    );

    test('one approval entry with none: the web\'s own words', () async {
      final c = await start(approvals: const []);
      c.applyFilter(f(['approvals']));
      await settle();
      expect(c.viewState.value, AppViewState.empty);
      expect(c.emptyText, 'No pending approvals.');
    });

    test('a failed approvals read keeps the old rows and says so', () async {
      final c = await start();
      c.applyFilter(f(['me', 'approved']));
      await settle();
      rig.routes['req.list'] = (_) => throw const SocketCallError('timeout');
      await c.approvals.reload();
      await settle();
      expect(ids(c.approvalCards), [3]);
      expect(c.isApprovalsStale, isTrue);
      expect(c.isApprovalsFailed, isFalse);
      expect(c.rows, isNotEmpty, reason: 'the records are not blocked');
    });

    test('a first read that fails does not block the records', () async {
      rig = InboxRig();
      addTearDown(rig.dispose);
      rig.routes['records.query'] = (_) => queryReply([record(1)]);
      rig.routes['req.list'] = (_) => throw const SocketCallError('timeout');
      final c = rig.controller..onInit();
      await settle();
      c.applyFilter(f(['me', 'allapprovals']));
      await settle();
      expect(c.rows, hasLength(1));
      expect(c.isApprovalsFailed, isTrue);
      expect(c.viewState.value, AppViewState.content);
    });
  });

  group('the panel', () {
    late InboxRig rig;
    late InboxController c;
    final panels = <InboxFilterController>[];

    Future<void> start({Map<String, int> facets = const {'leave': 2}}) async {
      rig = InboxRig();
      addTearDown(() {
        for (final p in panels) {
          p.onClose();
        }
        panels.clear();
        rig.dispose();
      });
      rig.routes['records.query'] = (a) => a['facets'] == true
          ? {
              'submissions': <Object>[],
              'structures': <String, Object>{},
              'total': 0,
              'formCounts': facets,
              'people': <String, Object>{},
            }
          : queryReply([record(1)]);
      rig.routes['records.people'] = (_) => {'team': <String>[]};
      rig.routes['req.list'] = (_) => {
        'requests': [for (final a in all) raw(a)],
        'total': all.length,
        'hasMore': false,
      };
      c = rig.controller..onInit();
      await settle();
    }

    InboxFilterController open(InboxFilter initial) {
      final p = InboxFilterController(
        inbox: rig.inbox,
        initial: initial,
        baseWhere: 'me',
        isTeamShown: false,
        forms: const {'leave': 'Leave', 'expense': 'Expense', 'other': 'Other'},
        onApply: c.applyFilter,
        onClear: c.clearFilter,
        approvals: c.approvals,
        wait: const Duration(milliseconds: 1),
      )..onInit();
      panels.add(p);
      return p;
    }

    Future<void> wait() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await settle();
    }

    test(
      'approval-only: Data offers the forms that have approvals, no ask',
      () async {
        await start();
        final before = rig.asked.where((a) => a == 'records.query').length;
        final p = open(f(['allapprovals']));
        await wait();
        expect(
          [for (final x in p.formChoices) x.label],
          ['Expense (2)', 'Leave (4)'],
        );
        expect(rig.asked.where((a) => a == 'records.query').length, before);
      },
    );

    test('mixed: the server counts and the approvals add up', () async {
      await start(facets: const {'leave': 2, 'other': 1});
      final p = open(f(['me', 'approved']));
      await wait();
      final labels = {for (final x in p.formChoices) x.id: x.label};
      expect(labels['leave'], 'Leave (2)');
      expect(labels['expense'], 'Expense (1)');
      expect(labels['other'], 'Other (1)');
    });

    test(
      'a form with no approval is let go under an approval-only choice',
      () async {
        await start();
        final p = open(f(['allapprovals'], forms: ['other', 'leave']));
        await wait();
        expect(p.draft.value.forms, ['leave']);
      },
    );

    test(
      'Advanced ticks show only when a named form has an approval flow',
      () async {
        await start();
        final p = open(f(['allapprovals']));
        await wait();
        expect(p.isApprovalOffered, isFalse);
        p.setForms(['leave']);
        expect(p.isApprovalOffered, isTrue);
        p.toggleApprovalPick('pending');
        expect(p.draft.value.approvalPick, ['pending']);
        expect(p.advancedCount, 1);
        expect(p.count, greaterThan(0));
        p.setForms(['other']);
        await wait();
        expect(
          p.draft.value.approvalPick,
          isEmpty,
          reason: 'the ticks go with the flow',
        );
      },
    );

    test('the ticks are applied and kept', () async {
      await start();
      final p = open(f(const [], forms: ['leave'], approvalPick: ['approved']));
      await wait();
      p.apply();
      await settle();
      expect(c.filter.value.approvalPick, ['approved']);
      expect(c.filterCount, 2);
    });
  });

  group('saved views', () {
    test('a filter with approval entries and ticks round-trips', () {
      final filter = f(
        ['me', 'approvals', 'escalations'],
        forms: ['leave'],
        approvalPick: ['pending', 'rejected'],
      );
      final setup = filter.toSetup();
      expect(setup['wheres'], ['me', 'approvals', 'escalations']);
      expect(setup['approvalPick'], ['pending', 'rejected']);
      final back = InboxFilter.fromSetup(setup);
      expect(back.wheres, filter.wheres);
      expect(back.approvalPick, filter.approvalPick);
      expect(back.forms, ['leave']);
    });

    test('one approval entry is the web\'s folder', () {
      for (final e in {
        'allapprovals': 'allapprovals',
        'approvals': 'approval',
        'approved': 'approved',
        'rejected': 'rejected',
      }.entries) {
        final setup = f([e.key]).toSetup();
        expect(setup['folder'], e.value);
        expect(setup['wheres'], isEmpty);
        expect(InboxFilter.fromSetup(setup).wheres, [e.key]);
      }
    });

    test('a web view with wheres of approvals opens', () {
      final web = {
        'folder': 'data',
        'lens': 'me',
        'kinds': <String>[],
        'dataForms': <String>[],
        'approvalPick': ['pending', 'nonsense'],
        'scopePick': <String>[],
        'wheres': ['approvals', 'approved', 'completed'],
        'teamMembers': <String>[],
        'blocks': <Object>[],
        'filters': {
          'forms': ['leave'],
        },
        'sort': 'latest',
        'timing': {
          'period': 'any',
          'from': '',
          'to': '',
          'hours': [0, 1440],
        },
      };
      final r = InboxSetup.restore(web);
      expect(r.filter.wheres, ['approvals', 'approved', 'completed']);
      expect(r.filter.approvalPick, ['pending']);
      final again = InboxSetup.compose(web, r.filter, r.scope);
      expect(again['wheres'], web['wheres']);
      expect(again['approvalPick'], ['pending']);
    });

    test('saving a view keeps what was ticked (compose over the base)', () {
      final base = {
        'approvalPick': ['approved'],
        'lens': 'team',
      };
      final out = InboxSetup.compose(
        base,
        f(const [], forms: ['leave'], approvalPick: ['rejected']),
        'me',
      );
      expect(out['approvalPick'], ['rejected']);
      expect(out['lens'], 'team');
      final cleared = InboxSetup.compose(base, InboxFilter.none, 'me');
      expect(cleared['approvalPick'], isEmpty);
    });
  });
}
