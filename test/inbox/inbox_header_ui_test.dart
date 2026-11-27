import 'package:connectum/core/theme/app_inbox.dart';
import 'package:connectum/features/inbox/inbox_view.dart';
import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:connectum/features/inbox/models/inbox_filter_chips.dart';
import 'package:connectum/features/inbox/widgets/approval_filter_bar.dart';
import 'package:connectum/features/inbox/widgets/inbox_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'inbox_screen_support.dart';

Map<String, dynamic> _req(int id) => {
  'id': id,
  'type': 'submission',
  'status': 'pending',
  'from': 'rhea',
  'fromName': 'Rhea Rao',
  'approvers': ['ana'],
  'direction': 'incoming',
  'canRespond': true,
  'createdTs': DateTime(2026, 11, 20, 9, id % 60).millisecondsSinceEpoch,
  'data': {
    'caption': 'Expense $id',
    'tstruct': 'expense',
    'stage': 1,
    'stages': 2,
    'summary': [
      {'caption': 'Amount', 'value': '120'},
    ],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<InboxRig> pump(
    WidgetTester t, {
    double width = 390,
    double scale = 1,
    int requests = 1,
    bool isStill = false,
    TextDirection dir = TextDirection.ltr,
  }) async {
    await t.pumpWidget(const SizedBox());
    Get.reset();
    final rig = InboxRig();
    addTearDown(rig.dispose);
    rig.routes['records.query'] = (a) => a['facets'] == true
        ? {
            'submissions': <Object>[],
            'structures': <String, Object>{},
            'total': 0,
            'formCounts': {'t': 2},
            'people': {
              'createdBy': ['me'],
            },
          }
        : queryReply([for (var i = 3; i > 0; i--) record(i)]);
    rig.routes['req.list'] = (_) => {
      'requests': [for (var i = 1; i <= requests; i++) _req(i)],
      'total': requests,
      'hasMore': false,
    };
    Get.put(rig.controller);
    addTearDown(Get.reset);
    t.view.physicalSize = Size(width, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => Directionality(
          textDirection: dir,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: isStill,
            ),
            child: child!,
          ),
        ),
        home: const InboxView(),
      ),
    );
    await settle(t);
    return rig;
  }

  final filterButton = find.byKey(const ValueKey('filter'));
  final close = find.byKey(const ValueKey('inbox-search-close'));

  group('the header row', () {
    for (final cfg in [(390.0, 1.0), (320.0, 1.0), (320.0, 1.5)]) {
      testWidgets('title, views chip, then the buttons at ${cfg.$1}px '
          'x${cfg.$2}', (t) async {
        await pump(t, width: cfg.$1, scale: cfg.$2);
        expect(t.takeException(), isNull);
        expect(find.byIcon(Icons.mail_outline_rounded), findsNothing);
        expect(find.byIcon(Icons.visibility_outlined), findsNothing);
        final title = t.getRect(find.text('Inbox'));
        final search = t.getRect(find.byTooltip('Search'));
        final chip = find.byIcon(Icons.filter_center_focus_rounded);
        // No separate row for the chip: the whole header is one row high.
        expect(title.height, lessThan(80));
        expect(t.getRect(find.byType(InboxView)).height, greaterThan(300));
        if (chip.evaluate().isNotEmpty) {
          final c = t.getRect(chip);
          expect(c.left, greaterThan(title.right - 0.5));
          expect(c.right, lessThanOrEqualTo(search.left + 0.5));
          expect((c.center.dy - search.center.dy).abs(), lessThan(14));
        }
        expect(
          t.getRect(find.byTooltip('Search')).right,
          lessThanOrEqualTo(cfg.$1),
        );
      });
    }

    testWidgets('the chip is centred between the title and the buttons', (
      t,
    ) async {
      await pump(t);
      final title = t.getRect(find.text('Inbox'));
      final search = t.getRect(find.byTooltip('Search'));
      final icon = find.byIcon(Icons.filter_center_focus_rounded);
      final chip = t.getRect(
        find.ancestor(of: icon, matching: find.byType(DecoratedBox)).first,
      );
      final mid = (title.right + search.left) / 2;
      expect((chip.center.dx - mid).abs(), lessThan(2));
    });

    testWidgets('the chip is gone on the Approvals tab', (t) async {
      final rig = await pump(t);
      expect(find.byIcon(Icons.filter_center_focus_rounded), findsOneWidget);
      rig.controller.openApprovals();
      await settle(t);
      expect(find.byIcon(Icons.filter_center_focus_rounded), findsNothing);
    });
  });

  group('the Records filter chips', () {
    testWidgets('none at all while no filter is on, never an All chip', (
      t,
    ) async {
      await pump(t);
      expect(find.byKey(const ValueKey('inbox-chip-bar')), findsNothing);
      expect(find.text('All'), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('a chip for each filter, and x removes it and reloads', (
      t,
    ) async {
      final rig = await pump(t, width: 900);
      final c = rig.controller;
      c.applyFilter(
        const InboxFilter(
          forms: ['t'],
          createdBy: ['me'],
          from: '2026-11-05',
          to: '2026-11-20',
          status: 'open',
        ),
      );
      await settle(t);
      expect(find.byKey(const ValueKey('inbox-chip-bar')), findsOneWidget);
      for (final id in ['form-t', 'createdBy-me', 'days', 'status']) {
        expect(find.byKey(ValueKey('inbox-selected-$id')), findsOneWidget);
      }
      expect(find.text('Created by Me'), findsOneWidget);
      expect(find.text('5 Nov 2026 to 20 Nov 2026'), findsOneWidget);
      expect(find.text('Open only'), findsOneWidget);
      final reads = rig.asked.where((a) => a == 'records.query').length;
      await t.tap(find.byKey(const ValueKey('inbox-selected-status')));
      await settle(t);
      expect(c.filter.value.status, isEmpty);
      expect(find.byKey(const ValueKey('inbox-selected-status')), findsNothing);
      expect(
        rig.asked.where((a) => a == 'records.query').length,
        greaterThan(reads),
      );
      for (final id in ['form-t', 'createdBy-me', 'days']) {
        await t.tap(find.byKey(ValueKey('inbox-selected-$id')));
        await settle(t);
      }
      expect(c.filter.value.filterCount(), 0);
      expect(find.byKey(const ValueKey('inbox-chip-bar')), findsNothing);
      expect(find.text('All'), findsNothing);
    });

    testWidgets('the row scrolls sideways at 320 px x1.5 with no overflow', (
      t,
    ) async {
      final rig = await pump(t, width: 320, scale: 1.5);
      rig.controller.applyFilter(
        const InboxFilter(
          forms: ['t'],
          createdBy: ['me'],
          sentTo: ['me'],
          status: 'closed',
        ),
      );
      await settle(t);
      expect(t.takeException(), isNull);
      final bar = find.byKey(const ValueKey('inbox-chip-bar'));
      expect(bar, findsOneWidget);
      await t.drag(
        find.descendant(of: bar, matching: find.byType(ListView)),
        const Offset(-200, 0),
      );
      await t.pump();
      expect(t.takeException(), isNull);
    });

    test('every part of the filter has a clear label', () {
      final chips = InboxFilterChips.of(
        InboxFilter(
          wheres: const ['approved', 'escalations'],
          forms: const ['leave'],
          createdBy: const ['me', 'rhea'],
          sentBy: const ['bob'],
          from: '2026-11-05',
          sort: InboxSort.oldest,
          approvalPick: const ['pending'],
          blocks: [
            InboxBlock(
              forms: const ['leave'],
              conditions: [InboxCondition(field: 'days', op: 'gt', value: '3')],
            ),
          ],
        ),
        formName: (id) => 'Leave request',
        personName: (u) => 'Name of $u',
      );
      expect(
        [for (final c in chips) c.label],
        [
          'Approved',
          'Escalations',
          'Leave request',
          'Created by Me',
          'Created by Name of rhea',
          'Sent by Name of bob',
          'From 5 Nov 2026',
          'Sort: Oldest',
          'Advanced: Leave request · days > 3',
          'Approval: Pending',
        ],
      );
      expect(chips.first.removed.wheres, ['escalations']);
    });
  });

  group('the search', () {
    testWidgets('tapping where the filter button was closes the search', (
      t,
    ) async {
      for (final wait in [0, 60, 150, 300, 600]) {
        final rig = await pump(t);
        final spot = t.getRect(filterButton).center;
        await t.tap(find.byTooltip('Search'));
        await t.pump();
        if (wait > 0) await t.pump(Duration(milliseconds: wait));
        expect(rig.controller.isSearchOpen.value, isTrue);
        await t.tapAt(spot);
        await settle(t);
        expect(
          rig.controller.isSearchOpen.value,
          isFalse,
          reason: 'after $wait ms',
        );
        expect(find.byType(InboxFilterPanel), findsNothing);
        expect(find.byType(InboxFilterPopupFrame), findsNothing);
        expect(filterButton, findsOneWidget);
      }
    });

    testWidgets('the filter button is hidden and dead while the search is '
        'open; the close circle has a 44 dp area', (t) async {
      await pump(t);
      await t.tap(find.byTooltip('Search'));
      await settle(t);
      final ignore = find.ancestor(
        of: filterButton,
        matching: find.byType(IgnorePointer),
      );
      expect(
        t.widgetList<IgnorePointer>(ignore).any((w) => w.ignoring),
        isTrue,
      );
      expect(t.getSize(close).width, greaterThanOrEqualTo(AppInbox.hit));
      expect(t.getSize(close).height, greaterThanOrEqualTo(AppInbox.hit));
      expect(
        (t.getRect(close).center - t.getRect(filterButton).center).distance,
        lessThan(1),
      );
    });

    testWidgets('opens and closes with the title and chip fading away', (
      t,
    ) async {
      final rig = await pump(t);
      Opacity titleFade() => t.widget<Opacity>(
        find
            .ancestor(of: find.text('Inbox'), matching: find.byType(Opacity))
            .first,
      );
      expect(titleFade().opacity, 1);
      await t.tap(find.byTooltip('Search'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 90));
      final mid = titleFade().opacity;
      expect(mid, lessThan(1));
      await t.pump(const Duration(milliseconds: 300));
      expect(titleFade().opacity, 0);
      expect(rig.controller.searchFocus.hasFocus, isTrue);
      rig.controller.closeSearch();
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(titleFade().opacity, greaterThan(0));
      await settle(t);
      expect(titleFade().opacity, 1);
      expect(close, findsNothing);
    });

    testWidgets('the clear x shows only with text; the count shows with a '
        'query', (t) async {
      final rig = await pump(t);
      await t.tap(find.byTooltip('Search'));
      await settle(t);
      final clear = find.byKey(const ValueKey('inbox-search-clear'));
      final count = find.byKey(const ValueKey('inbox-search-count'));
      expect(clear, findsNothing);
      expect(count, findsNothing);
      await t.enterText(find.byType(TextField), 'Record 2');
      await settle(t);
      expect(clear, findsOneWidget);
      expect(count, findsOneWidget);
      expect(find.text('1 result'), findsOneWidget);
      await t.tap(clear);
      await settle(t);
      expect(rig.controller.searchField.text, isEmpty);
      expect(clear, findsNothing);
      expect(count, findsNothing);
      expect(rig.controller.isSearchOpen.value, isTrue);
    });

    testWidgets('reduced motion: a cross-fade, still works at 320 px x1.5', (
      t,
    ) async {
      final rig = await pump(t, width: 320, scale: 1.5, isStill: true);
      await t.tap(find.byTooltip('Search'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(rig.controller.isSearchOpen.value, isTrue);
      expect(t.takeException(), isNull);
      await t.tap(close);
      await settle(t);
      expect(rig.controller.isSearchOpen.value, isFalse);
      expect(t.takeException(), isNull);
    });

    testWidgets('right to left opens and closes', (t) async {
      final rig = await pump(t, dir: TextDirection.rtl);
      await t.tap(find.byTooltip('Search'));
      await settle(t);
      await t.tap(close);
      await settle(t);
      expect(rig.controller.isSearchOpen.value, isFalse);
      expect(t.takeException(), isNull);
    });
  });

  group('the tab pills', () {
    final records = find.byKey(const ValueKey('inbox-records-count'));
    final approvals = find.byKey(const ValueKey('inbox-approvals-count'));

    Color ink(WidgetTester t, Finder pill) => t
        .widget<Text>(find.descendant(of: pill, matching: find.byType(Text)))
        .style!
        .color!;

    testWidgets('each pill has its own tone', (t) async {
      await pump(t);
      expect(records, findsOneWidget);
      expect(approvals, findsOneWidget);
      expect(ink(t, records), AppInbox.recordsCountTone.strong);
      expect(ink(t, approvals), AppInbox.approvalsCountTone.strong);
      expect(ink(t, records), isNot(ink(t, approvals)));
    });

    testWidgets('the approvals pill shows 0 in the muted tone', (t) async {
      await pump(t, requests: 0);
      expect(approvals, findsOneWidget);
      expect(
        find.descendant(of: approvals, matching: find.text('0')),
        findsOneWidget,
      );
      expect(ink(t, approvals), AppInbox.emptyCountTone.strong);
    });

    for (final n in [1, 12, 123, 1234]) {
      testWidgets('the approvals pill is compact with $n', (t) async {
        await pump(t, requests: n);
        expect(approvals, findsOneWidget);
        final text = find.descendant(of: approvals, matching: find.text('$n'));
        expect(text, findsOneWidget);
        final r = t.getRect(approvals);
        expect(r.height, lessThan(30));
        expect(r.width, greaterThanOrEqualTo(r.height - 0.5));
        expect(r.width, lessThan(r.height + 11.0 * '$n'.length + 8));
        expect((r.center.dy - t.getRect(text).center.dy).abs(), lessThan(1.5));
      });
    }
  });

  group('the header filter button', () {
    testWidgets('opens the records sheet on Records, the quick popup on '
        'Approvals, and follows the tab', (t) async {
      final rig = await pump(t);
      expect(find.byKey(const ValueKey('filter')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('filter')));
      await settle(t);
      expect(find.byType(InboxFilterPanel), findsOneWidget);
      await t.tapAt(const Offset(10, 880));
      await settle(t);

      await t.tap(find.text('Approvals').first);
      await settle(t);
      expect(rig.controller.isApprovalsOpen, isTrue);
      expect(find.byKey(const ValueKey('approvals-filter')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter')), findsNothing);
      await t.tap(find.byKey(const ValueKey('approvals-filter')));
      await settle(t);
      expect(find.byType(ApprovalQuickPanel), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Entries'), findsOneWidget);
      expect(find.byType(InboxFilterPanel), findsNothing);
      // No second filter button in the chip row any more.
      expect(
        find.byKey(const ValueKey('approval-filters-button')),
        findsNothing,
      );
      await t.tap(find.text('Clear'));
      await settle(t);

      await t.drag(find.byType(PageView), const Offset(400, 0));
      await settle(t);
      expect(rig.controller.isApprovalsOpen, isFalse);
      expect(find.byKey(const ValueKey('filter')), findsOneWidget);
      expect(find.byKey(const ValueKey('approvals-filter')), findsNothing);
    });

    testWidgets('a picked status shows as a removable chip under the tabs', (
      t,
    ) async {
      final rig = await pump(t);
      await t.tap(find.text('Approvals').first);
      await settle(t);
      expect(find.byKey(const ValueKey('approval-chip-bar')), findsNothing);
      await t.tap(find.byKey(const ValueKey('approvals-filter')));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('approval-status-pending')));
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(find.text('Apply'));
      await settle(t);
      expect(
        find.byKey(const ValueKey('approval-selected-status')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('approval-selected-status')));
      await settle(t);
      expect(find.byKey(const ValueKey('approval-chip-bar')), findsNothing);
      expect(rig.controller.approvals.primary.value.name, 'all');
    });
  });
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
