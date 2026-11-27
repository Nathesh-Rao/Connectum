import 'package:connectum/features/inbox/inbox_view.dart';
import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:connectum/features/inbox/models/inbox_tab.dart';
import 'package:connectum/features/inbox/widgets/inbox_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'inbox_screen_support.dart';

Map<String, dynamic> req(int id, {bool canRespond = true}) => {
  'id': id,
  'type': 'submission',
  'status': 'pending',
  'from': 'rhea',
  'fromName': 'Rhea Rao',
  'approvers': ['ana'],
  'direction': canRespond ? 'incoming' : 'outgoing',
  'canRespond': canRespond,
  'createdTs': DateTime(2026, 11, 20, 9, id).millisecondsSinceEpoch,
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
    TextDirection dir = TextDirection.ltr,
    int records = 3,
    List<Map<String, dynamic>>? requests,
  }) async {
    final rig = InboxRig();
    addTearDown(rig.dispose);
    rig.routes['records.query'] = (_) =>
        queryReply([for (var i = records; i > 0; i--) record(i)]);
    rig.routes['req.list'] = (_) => {
      'requests': requests ?? [req(1), req(2, canRespond: false)],
      'total': (requests ?? [req(1), req(2)]).length,
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
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: const InboxView(),
      ),
    );
    await settle(t);
    return rig;
  }

  final thumb = find.byKey(const ValueKey('inbox-tab-thumb'));

  group('the tab bar', () {
    testWidgets('a tap switches the page and the thumb slides with it', (
      t,
    ) async {
      final rig = await pump(t);
      final c = rig.controller;
      final start = t.getRect(thumb).left;
      expect(c.isApprovalsOpen, isFalse);
      await t.tap(find.text('Approvals').first);
      await settle(t);
      expect(c.isApprovalsOpen, isTrue);
      expect(t.getRect(thumb).left, greaterThan(start + 100));
      expect(find.text('Expense 1'), findsWidgets);
      await t.tap(find.text('Records').first);
      await settle(t);
      expect(c.isApprovalsOpen, isFalse);
      expect(t.getRect(thumb).left, closeTo(start, 0.5));
    });

    testWidgets('a swipe switches the tab and keeps the thumb in sync', (
      t,
    ) async {
      final rig = await pump(t);
      final c = rig.controller;
      final start = t.getRect(thumb).left;
      await t.drag(find.byType(PageView), const Offset(-320, 0));
      await settle(t);
      expect(c.tabIndex.value, 1);
      expect(t.getRect(thumb).left, greaterThan(start + 100));
      await t.drag(find.byType(PageView), const Offset(320, 0));
      await settle(t);
      expect(c.tabIndex.value, 0);
      expect(t.getRect(thumb).left, closeTo(start, 0.5));
    });

    testWidgets('the Approvals pill counts every request listed', (t) async {
      final rig = await pump(t);
      final pill = find.byKey(const ValueKey('inbox-approvals-count'));
      expect(pill, findsOneWidget);
      expect(
        find.descendant(of: pill, matching: find.text('2')),
        findsOneWidget,
      );
      expect(rig.controller.badgeOf(InboxTab.approvals), 1);
    });

    testWidgets('the Approvals pill stays at zero', (t) async {
      await pump(t, requests: const []);
      final pill = find.byKey(const ValueKey('inbox-approvals-count'));
      expect(pill, findsOneWidget);
      expect(
        find.descendant(of: pill, matching: find.text('0')),
        findsOneWidget,
      );
    });

    testWidgets('each tab keeps its own scroll position', (t) async {
      final rig = await pump(t, records: 12);
      final c = rig.controller;
      await t.drag(find.byType(InboxCard).first, const Offset(0, -300));
      await settle(t);
      final at = c.scroll.offset;
      expect(at, greaterThan(100));
      await t.drag(find.byType(PageView), const Offset(-320, 0));
      await settle(t);
      await t.drag(find.byType(PageView), const Offset(320, 0));
      await settle(t);
      expect(c.scroll.offset, at);
    });

    testWidgets('a filter acts on the Records tab', (t) async {
      final rig = await pump(t);
      final c = rig.controller;
      c.openApprovals();
      await settle(t);
      expect(c.isApprovalsOpen, isTrue);
      c.applyFilter(const InboxFilter(wheres: ['me']));
      await settle(t);
      expect(c.isApprovalsOpen, isFalse);
      expect(t.getRect(thumb).left, lessThan(60));
    });

    testWidgets('the filter button is on both tabs, each with its own panel', (
      t,
    ) async {
      final rig = await pump(t);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.byTooltip('Filter and sort'), findsOneWidget);
      rig.controller.openApprovals();
      await settle(t);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.byTooltip('Filter the approvals'), findsOneWidget);
      expect(find.byTooltip('Filter and sort'), findsNothing);
    });
  });

  group('the search', () {
    testWidgets('opens as a bar with only the field, and folds away', (
      t,
    ) async {
      final rig = await pump(t);
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.byTooltip('Search'));
      await settle(t);
      expect(find.byType(TextField), findsOneWidget);
      expect(rig.controller.isSearchOpen.value, isTrue);
      final bar = find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(ClipRRect),
      );
      expect(
        find.descendant(
          of: bar.first,
          matching: find.byIcon(Icons.tune_rounded),
        ),
        findsNothing,
      );
      await t.enterText(find.byType(TextField), 'Record 2');
      await settle(t);
      expect(rig.controller.query.value, 'Record 2');
      await t.tap(find.byTooltip('Close search'));
      await settle(t);
      expect(find.byType(TextField), findsNothing);
      expect(rig.controller.query.value, isEmpty);
    });

    testWidgets('each tab keeps its own text', (t) async {
      final rig = await pump(t);
      final c = rig.controller;
      await t.tap(find.byTooltip('Search'));
      await settle(t);
      await t.enterText(find.byType(TextField), 'Record 2');
      await settle(t);
      await t.tap(find.text('Approvals').first);
      await settle(t);
      expect(c.searchField.text, isEmpty);
      await t.enterText(find.byType(TextField), 'Expense 1');
      await settle(t);
      expect(c.approvalsQuery.value, 'Expense 1');
      expect(c.query.value, 'Record 2');
      await t.tap(find.text('Records').first);
      await settle(t);
      expect(c.searchField.text, 'Record 2');
      expect(c.query.value, 'Record 2');
    });
  });

  group('the views chip', () {
    testWidgets('names the open view, marks a change and opens the panel', (
      t,
    ) async {
      final rig = await pump(t);
      expect(find.text('Default View'), findsOneWidget);
      expect(find.byKey(const ValueKey('view-changed')), findsNothing);
      rig.controller.applyFilter(const InboxFilter(forms: ['t']));
      await settle(t);
      expect(find.byKey(const ValueKey('view-changed')), findsOneWidget);
      await t.tap(find.text('Default View'));
      await settle(t);
      expect(find.text('Save view'), findsOneWidget);
      expect(find.text('Create view'), findsOneWidget);
    });
  });

  group('refresh', () {
    testWidgets('the header has no Refresh button and no spinner', (t) async {
      final rig = await pump(t);
      expect(find.byTooltip('Refresh'), findsNothing);
      expect(find.bySemanticsLabel('Refresh'), findsNothing);
      rig.controller.isRefreshing.value = true;
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      rig.controller.isRefreshing.value = false;
    });

    testWidgets('pull to refresh reads again on both tabs', (t) async {
      final rig = await pump(t);
      final before = rig.argsOf('records.query').length;
      await t.fling(find.byType(InboxCard).first, const Offset(0, 500), 1000);
      await settle(t);
      expect(rig.argsOf('records.query').length, greaterThan(before));
      final reads = rig.asked.where((a) => a == 'req.list').length;
      rig.controller.openApprovals();
      await settle(t);
      await t.fling(find.text('Expense 1').first, const Offset(0, 500), 1000);
      await settle(t);
      expect(
        rig.asked.where((a) => a == 'req.list').length,
        greaterThan(reads),
      );
    });
  });

  testWidgets('right to left: the thumb starts at the right and follows', (
    t,
  ) async {
    final rig = await pump(t, dir: TextDirection.rtl);
    expect(t.takeException(), isNull);
    final start = t.getRect(thumb).left;
    expect(start, greaterThan(150));
    await t.tap(find.text('Approvals').first);
    await settle(t);
    expect(rig.controller.isApprovalsOpen, isTrue);
    expect(t.getRect(thumb).left, lessThan(start - 100));
    await t.tap(find.byTooltip('Search'));
    await settle(t);
    expect(find.byType(TextField), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('320 px, text x1.5: header, tab bar, open search, no overflow', (
    t,
  ) async {
    final rig = await pump(t, width: 320, scale: 1.5);
    expect(t.takeException(), isNull);
    rig.controller.applyFilter(const InboxFilter(forms: ['t']));
    await settle(t);
    expect(t.takeException(), isNull);
    await t.tap(find.byTooltip('Search'));
    await settle(t);
    expect(t.takeException(), isNull);
    await t.tap(find.byTooltip('Close search'));
    await settle(t);
    await t.tap(find.text('Approvals').first);
    await settle(t);
    expect(t.takeException(), isNull);
  });
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
