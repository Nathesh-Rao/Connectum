import 'package:connectum/features/inbox/inbox_filter_controller.dart';
import 'package:connectum/features/inbox/inbox_view.dart';
import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:connectum/features/inbox/widgets/inbox_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'inbox_screen_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;

  Future<void> pumpFor(
    WidgetTester t, {
    double width = 320,
    double scale = 1.5,
  }) async {
    t.view.physicalSize = Size(width, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
  }

  Widget host(Widget child, double scale) => MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: c!,
    ),
    home: Scaffold(body: SafeArea(child: child)),
  );

  Future<void> pumpLong(WidgetTester t, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('a block with conditions of every kind fits 320 px at text '
      'scale 1.5', (t) async {
    rig = InboxRig();
    rig.routes['ai.enterprise'] = (_) => sourcesReply();
    rig.routes['records.query'] = (_) => queryReply([record(1)]);
    rig.routes['records.people'] = (_) => {
      'team': <String>[],
      'sentBy': <String>[],
      'sentTo': <String>[],
    };
    await pumpFor(t);
    final block = InboxBlock(
      id: 'b1',
      forms: const ['t'],
      conditions: [
        InboxCondition(
          id: 'c1',
          field: 'title',
          op: 'contains',
          value: 'a long value to type',
        ),
        InboxCondition(
          id: 'c2',
          field: 'hours',
          op: 'between',
          value: '1',
          value2: '5',
          join: 'or',
        ),
        InboxCondition(id: 'c3', field: 'due', op: 'gte', value: '2026-11-01'),
        InboxCondition(id: 'c4', field: 'ok', op: 'eq', value: 'true'),
      ],
    );
    final panel = InboxFilterController(
      inbox: rig.inbox,
      initial: InboxFilter(blocks: [block]),
      baseWhere: 'me',
      isTeamShown: false,
      forms: const {'t': 'Thing', 'u': 'Other'},
      onApply: (_) {},
      onClear: () {},
      fieldKinds: rig.fieldKinds,
      wait: const Duration(milliseconds: 1),
    )..onInit();
    addTearDown(() {
      panel.onClose();
      rig.dispose();
    });
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pumpWidget(host(InboxFilterPanel(panel: panel), 1.5));
    await pumpLong(t);
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(
      find.text('Add a condition'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Add a condition'), findsOneWidget);
    expect(find.text('Where'), findsWidgets);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(
      find.text('Or'),
      findsNWidgets(3),
      reason: 'a join for each later condition',
    );
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('2026-11-01'), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'no overflow');
    // the add-condition button and a row action are real taps
    await t.tap(find.text('Add a condition'));
    await pumpLong(t);
    expect(panel.draft.value.blocks.single.conditions.length, 5);
    await t.tap(find.bySemanticsLabel('Remove condition 5'));
    await pumpLong(t);
    expect(panel.draft.value.blocks.single.conditions.length, 4);
    expect(t.takeException(), isNull);
  });

  testWidgets('a block with two forms says conditions are not used; a failed '
      'read says they are not available', (t) async {
    rig = InboxRig();
    rig.routes['ai.enterprise'] = (_) => throw StateError('x');
    rig.routes['records.query'] = (_) => queryReply([]);
    rig.routes['records.people'] = (_) => {
      'team': <String>[],
      'sentBy': <String>[],
      'sentTo': <String>[],
    };
    await pumpFor(t);
    final panel = InboxFilterController(
      inbox: rig.inbox,
      initial: InboxFilter(
        blocks: [
          InboxBlock(id: 'b1', forms: const ['t', 'u']),
          InboxBlock(id: 'b2', forms: const ['t']),
        ],
      ),
      baseWhere: 'me',
      isTeamShown: false,
      forms: const {'t': 'Thing', 'u': 'Other'},
      onApply: (_) {},
      onClear: () {},
      fieldKinds: rig.fieldKinds,
      wait: const Duration(milliseconds: 1),
    );
    panel.isAdvanced.value = true;
    panel.onInit();
    addTearDown(() {
      panel.onClose();
      rig.dispose();
    });
    await t.pumpWidget(host(InboxFilterPanel(panel: panel), 1.5));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await pumpLong(t);
    expect(
      find.text(InboxFilterController.conditionsManyFormsText),
      findsOneWidget,
    );
    expect(find.text('Conditions are not available right now'), findsOneWidget);
    expect(
      find.text('Add more data'),
      findsOneWidget,
      reason: 'blocks still work',
    );
  });

  testWidgets(
    'Timeline: one heading per day, newest first, a card under each',
    (t) async {
      rig = InboxRig();
      final day = DateTime(2026, 11, 24, 9).millisecondsSinceEpoch;
      final yesterday = DateTime(2026, 11, 23, 22).millisecondsSinceEpoch;
      final older = DateTime(2026, 11, 2, 10).millisecondsSinceEpoch;
      rig.routes['records.query'] = (_) => queryReply([
        {
          ...record(3, values: {'title': 'Third'}),
          'ts': day,
        },
        {
          ...record(2, values: {'title': 'Second'}),
          'ts': yesterday,
        },
        {
          ...record(1, values: {'title': 'First'}),
          'ts': older,
        },
      ]);
      rig.routes['records.people'] = (_) => {
        'team': <String>[],
        'sentBy': <String>[],
        'sentTo': <String>[],
      };
      await pumpFor(t, width: 390, scale: 1);
      final c = rig.controller..onInit();
      Get.put(c);
      addTearDown(() {
        Get.reset();
        rig.dispose();
      });
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      c.applyFilter(const InboxFilter(wheres: ['timeline']));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pumpWidget(host(const InboxView(), 1));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Nov 2, 2026'), findsOneWidget);
      final today = t.getTopLeft(find.text('Today')).dy;
      final yest = t.getTopLeft(find.text('Yesterday')).dy;
      final old = t.getTopLeft(find.text('Nov 2, 2026')).dy;
      expect(today < yest && yest < old, isTrue);
      expect(find.text('Third'), findsOneWidget);
      expect(t.getTopLeft(find.text('Third')).dy, greaterThan(today));
      expect(t.getTopLeft(find.text('Third')).dy, lessThan(yest));
      // without Timeline there are no headings
      c.clearFilter();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Yesterday'), findsNothing);
    },
  );
}
