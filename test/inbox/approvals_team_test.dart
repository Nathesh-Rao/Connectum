import 'package:connectum/features/inbox/inbox_controller.dart';
import 'package:connectum/features/inbox/models/approval_chips.dart';
import 'package:connectum/features/inbox/models/approval_entries.dart';
import 'package:connectum/features/inbox/models/approval_rules.dart';
import 'package:connectum/features/inbox/models/inbox_tab.dart';
import 'package:connectum/features/inbox/widgets/approval_filter_bar.dart';
import 'package:connectum/features/inbox/widgets/approvals_pane.dart';
import 'package:connectum/features/inbox/widgets/inbox_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';
import 'inbox_support.dart';

Map<String, dynamic> req(
  int id, {
  String status = 'pending',
  String direction = 'incoming',
  bool canRespond = false,
  String from = 'zed',
  String? resolvedBy,
  bool returned = false,
  bool team = false,
  int? createdTs,
}) => {
  'id': id,
  'type': 'submission',
  'status': status,
  'from': from,
  'fromUser': from,
  'fromName': from,
  'approvers': ['ana'],
  'direction': direction,
  'canRespond': canRespond,
  'createdTs': createdTs ?? 1000 + id,
  'resolvedBy': ?resolvedBy,
  if (returned) 'returned': true,
  if (team) 'team': true,
  'tstruct': 'leave',
  'data': {'caption': 'Leave $id'},
};

Map<String, dynamic> page(List<Map<String, dynamic>> rows) => {
  'requests': rows,
  'total': rows.length,
  'hasMore': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;

  InboxController start({
    int reports = 0,
    List<Map<String, dynamic>> own = const [],
    List<Map<String, dynamic>>? team,
  }) {
    rig = InboxRig();
    addTearDown(rig.dispose);
    rig.routes['records.query'] = (_) => queryReply([record(1)]);
    rig.routes['records.counts'] = (_) => countsReply(reports: reports);
    rig.routes['req.list'] = (_) => page(own);
    rig.routes['req.team'] = (_) =>
        team == null ? throw UnimplementedError('older server') : page(team);
    rig.controller.onInit();
    return rig.controller;
  }

  final own = [
    req(1, direction: 'incoming', canRespond: true, from: 'rhea'),
    req(2, direction: 'outgoing', from: 'ana'),
    req(
      3,
      status: 'accepted',
      direction: 'incoming',
      from: 'sam',
      resolvedBy: 'ana',
    ),
  ];
  final team = [
    req(1, from: 'rhea', direction: 'other', team: true),
    req(
      4,
      status: 'rejected',
      from: 'sam',
      direction: 'other',
      resolvedBy: 'ana',
      returned: true,
      team: true,
    ),
    req(5, from: 'sam', direction: 'other', team: true),
  ];

  group('the Me / My Team toggle', () {
    test('a person with no reports has no toggle and no req.team', () async {
      final c = start(own: own, team: team);
      await settle();
      expect(c.approvals.hasTeam, isFalse);
      expect(rig.asked, isNot(contains('req.team')));
      c.approvals.pickSide(ApprovalSide.team);
      expect(c.approvals.effectiveSide, ApprovalSide.me);
      expect(c.approvals.side.value, ApprovalSide.me);
    });

    test(
      'with reports, req.team is read and the toggle switches the tab',
      () async {
        final c = start(reports: 2, own: own, team: team);
        await settle();
        final a = c.approvals;
        expect(a.hasTeam, isTrue);
        expect(rig.asked, contains('req.team'));
        // Me side, All: the person's own entries over the pooled requests.
        // 5 is a report's request that waits for nobody I can answer for: not
        // in any entry of mine.
        expect([for (final r in a.rows) r.id], [4, 3, 2, 1]);
        a.pickSide(ApprovalSide.team);
        // Team side, All: 1 (waits for me), 3 (I approved), 4 (returned), 5.
        expect({for (final r in a.rows) r.id}, {1, 3, 4, 5});
        expect(
          {for (final e in a.primaryCounts.entries) e.key.name: e.value},
          {'all': 4, 'pending': 1, 'approved': 1, 'requests': 4, 'rejected': 1},
        );
      },
    );

    test(
      'a request in both lists is the person\'s own (it has the buttons)',
      () async {
        final c = start(reports: 1, own: own, team: team);
        await settle();
        final a = c.approvals;
        final one = a.pool.where((r) => r.id == 1).single;
        expect(one.isTeam, isFalse);
        expect(one.canRespond, isTrue);
        expect(ApprovalRules.actionsFor(one), isNotEmpty);
      },
    );

    test(
      'a returned team request is a rejection on the My Team side',
      () async {
        final c = start(reports: 1, own: own, team: team);
        await settle();
        final a = c.approvals..pickSide(ApprovalSide.team);
        a.pickPrimary(ApprovalPrimary.rejected);
        expect([for (final r in a.rows) r.id], [4]);
        expect(a.rows.single.returned, isTrue);
      },
    );

    test('team rows are read only: no buttons without canRespond', () async {
      final c = start(reports: 1, own: own, team: team);
      await settle();
      for (final r in c.approvals.pool.where((r) => r.id == 4 || r.id == 5)) {
        expect(ApprovalRules.actionsFor(r), isEmpty, reason: '${r.id}');
      }
    });

    test(
      'an error of req.team is an empty team list, the tab still works',
      () async {
        final c = start(reports: 1, own: own);
        await settle();
        final a = c.approvals;
        expect(a.hasTeam, isTrue);
        expect(a.approvals.team, isEmpty);
        expect(a.hasError, isFalse);
        expect([for (final r in a.rows) r.id].toSet(), {1, 2, 3});
        // No report is known, so no request is a report's.
        a.pickSide(ApprovalSide.team);
        expect(a.rows, isEmpty);
      },
    );

    test('reports arriving late read the team and show the toggle', () async {
      final c = start(own: own, team: team);
      var reads = 0;
      rig.routes['records.counts'] = (_) =>
          countsReply(reports: reads++ == 0 ? 0 : 1);
      await settle();
      expect(rig.asked, isNot(contains('req.team')));
      await c.load();
      await settle();
      expect(c.approvals.hasTeam, isTrue);
      expect(rig.asked, contains('req.team'));
    });

    test(
      'the badge keeps its rule: pending and canRespond, own list only',
      () async {
        final c = start(reports: 1, own: own, team: team);
        await settle();
        expect(c.approvals.count, 1);
        expect(c.badgeOf(InboxTab.approvals), 1);
      },
    );

    test('the toggle and chips are never part of a saved view', () async {
      final c = start(reports: 1, own: own, team: team);
      await settle();
      c.approvals
        ..pickSide(ApprovalSide.team)
        ..pickPrimary(ApprovalPrimary.rejected);
      expect(c.isViewChanged, isFalse);
    });

    test(
      'a "Review approval" request opens the tab with no filter set',
      () async {
        final c = start(reports: 1, own: own, team: team);
        await settle();
        c.approvals
          ..pickSide(ApprovalSide.team)
          ..pickPrimary(ApprovalPrimary.rejected)
          ..toggleChip(ApprovalChipGroup.kind, 'form');
        rig.shell.approvalsRequest.value = true;
        await settle();
        expect(c.isApprovalsOpen, isTrue);
        expect(c.approvals.primary.value, ApprovalPrimary.all);
        expect(c.approvals.side.value, ApprovalSide.me);
        expect(c.approvals.hasChipsOn, isFalse);
      },
    );

    test(
      'the secondary chips count over the rows of the chip and side',
      () async {
        final c = start(reports: 1, own: own, team: team);
        await settle();
        final a = c.approvals..pickPrimary(ApprovalPrimary.pending);
        final dir = a.chipViews
            .expand((g) => g)
            .where((v) => v.group == ApprovalChipGroup.direction);
        // Pending, Me side: #1 (to me, waits) and #2 (from me).
        expect(
          {for (final v in dir) v.key: v.count},
          {'from_me': 1, 'not_from_me': 1, 'to_me': 1, 'not_to_me': 1},
        );
      },
    );
  });

  group('the pane', () {
    Future<void> pump(WidgetTester tester, {double scale = 1}) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: c!,
          ),
          home: Scaffold(
            body: Column(
              children: [
                Builder(
                  builder: (context) => TextButton(
                    key: const ValueKey('approval-filters-button'),
                    onPressed: () => ApprovalFilterPopup.show(
                      context,
                      rig.controller.approvals,
                    ),
                    child: const Text('filters'),
                  ),
                ),
                Expanded(
                  child: ApprovalsPane(controller: rig.controller.approvals),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> openPopup(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('approval-filters-button')));
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> apply(WidgetTester tester) async {
      await tester.tap(find.text('Apply'));
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('nothing selected: no chip row, no All chip', (tester) async {
      final c = start(own: own);
      await tester.runAsync(settle);
      await pump(tester, scale: 1.5);
      expect(find.byKey(const ValueKey('approval-chip-bar')), findsNothing);
      expect(find.byKey(const ValueKey('approval-selected-all')), findsNothing);
      expect(find.text('Pending 2'), findsNothing);
      expect(c.approvals.hasTeam, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the popup: Status with counts, Entries, no Scope without '
        'reports', (tester) async {
      start(own: own);
      await tester.runAsync(settle);
      await pump(tester, scale: 1.5);
      await openPopup(tester);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Scope'), findsNothing);
      expect(find.text('Entries'), findsOneWidget);
      expect(find.text('All 3'), findsOneWidget);
      expect(find.text('Pending 2'), findsOneWidget);
      expect(find.text('Approved 1'), findsOneWidget);
      expect(find.text('Requests 3'), findsOneWidget);
      expect(find.text('Rejected 0'), findsOneWidget);
      expect(find.textContaining('Sent to me'), findsOneWidget);
      expect(find.textContaining('Pending with me'), findsOneWidget);
      expect(find.textContaining('Sent by team'), findsNothing);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Apply selects a status: a chip with an x, '
        'the x removes it', (tester) async {
      final c = start(own: own);
      await tester.runAsync(settle);
      await pump(tester, scale: 1.5);
      await openPopup(tester);
      await tester.tap(find.text('Pending 2'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.approvals.primary.value, ApprovalPrimary.all);
      await apply(tester);
      expect(c.approvals.primary.value, ApprovalPrimary.pending);
      final chip = find.byKey(const ValueKey('approval-selected-status'));
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.byIcon(Icons.close_rounded)),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('approval-selected-all')), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(chip);
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.approvals.primary.value, ApprovalPrimary.all);
      expect(find.byKey(const ValueKey('approval-chip-bar')), findsNothing);
    });

    testWidgets('a zero-count option is dimmed and still takes a tap', (
      tester,
    ) async {
      final c = start(own: own);
      await tester.runAsync(settle);
      await pump(tester, scale: 1.5);
      await openPopup(tester);
      final zero = find.byKey(const ValueKey('approval-status-rejected'));
      await tester.tap(zero);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<InboxFilterChip>(zero).isDimmed, isTrue);
      expect(tester.widget<InboxFilterChip>(zero).isSelected, isTrue);
      await apply(tester);
      expect(c.approvals.primary.value, ApprovalPrimary.rejected);
      expect(c.approvals.rows, isEmpty);
    });

    testWidgets('Entries: a ticked entry is a chip of its own, the rules stay '
        'the entry rules', (tester) async {
      final c = start(own: own);
      await tester.runAsync(settle);
      await pump(tester, scale: 1.5);
      await openPopup(tester);
      final entry = find.byKey(
        ValueKey('approval-entry-${ApprovalEntry.pendingWithMe.name}'),
      );
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pump(const Duration(milliseconds: 300));
      await apply(tester);
      expect(c.approvals.panel.value.entries, [ApprovalEntry.pendingWithMe]);
      expect(
        find.byKey(
          ValueKey('approval-selected-${ApprovalEntry.pendingWithMe.name}'),
        ),
        findsOneWidget,
      );
      final who = c.approvals.whoOf;
      expect(
        c.approvals.rows.every(
          (a) => ApprovalEntries.inEntry(a, ApprovalEntry.pendingWithMe, who),
        ),
        isTrue,
      );
      expect(c.approvals.rows, isNotEmpty);
    });

    testWidgets('with reports Scope shows; My Team is a chip, Clear resets', (
      tester,
    ) async {
      final c = start(reports: 1, own: own, team: team);
      await tester.runAsync(settle);
      await pump(tester, scale: 1.5);
      await openPopup(tester);
      expect(find.text('Scope'), findsOneWidget);
      expect(find.text('Me'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('approval-scope-team')));
      await tester.pump(const Duration(milliseconds: 300));
      await apply(tester);
      expect(c.approvals.effectiveSide, ApprovalSide.team);
      expect(
        find.byKey(const ValueKey('approval-selected-scope')),
        findsOneWidget,
      );
      await openPopup(tester);
      await tester.tap(find.text('Clear'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(c.approvals.effectiveSide, ApprovalSide.me);
      expect(find.byKey(const ValueKey('approval-chip-bar')), findsNothing);
    });

    testWidgets('the popup fits 320 px at text x1.5 with every section', (
      tester,
    ) async {
      start(reports: 1, own: own, team: team);
      await tester.runAsync(settle);
      await pump(tester, scale: 1.5);
      await openPopup(tester);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -600),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });
}
