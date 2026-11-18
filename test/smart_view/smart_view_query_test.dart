import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_radius.dart';
import 'package:connectum/core/widgets/app_bubble_surface.dart';
import 'package:connectum/core/widgets/app_button.dart';
import 'package:connectum/core/widgets/app_text_field.dart';
import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/smart_view/engine/sv_engine.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/sv_prefs.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:connectum/features/smart_view/smart_view_view.dart';
import 'package:connectum/features/smart_view/widgets/smart_view_table.dart';
import 'package:connectum/features/smart_view/widgets/sv_filter_sheet.dart';
import 'package:connectum/features/smart_view/widgets/sv_pill.dart';
import 'package:connectum/features/tickets/ticket_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';
import 'sv_support.dart';

class _Connectivity extends ConnectivityService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {
    state.value = AppConnectivity.online;
  }

  @override
  void attachSocket(Rx<SocketState> socketState) {}
}

/// Bounded pumps: never pumpAndSettle.
Future<void> pumpFor(WidgetTester tester, [int ms = 600]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _titles = [
  ('Printer jammed', 'Delivery', '2026-11-20', 2.5, 'Open'),
  ('Router down', 'Billing', '2026-10-02', 4, 'In progress'),
  ('Alpha invoice', 'Billing', '', 1, 'Closed'),
  ('Laptop request', 'Delivery', '2026-12-05', 8, 'Open'),
  ('Badge lost', 'Support', '2026-11-02', 3, 'Open'),
  ('Zeta audit', 'Support', '2026-11-30', 12, 'Closed'),
];

List<SvRow> _rows() => [
  for (var i = 0; i < _titles.length; i++)
    SvRow.tryParse({
      'id': i + 1,
      'by': 'svcapcpw1ann',
      'byName': 'Ann Rao',
      'ts': 1794833216000 + i * 60000,
      'tstruct': 'tickets',
      'canEdit': true,
      'values': {
        'title': _titles[i].$1,
        'area': _titles[i].$2,
        'due': _titles[i].$3,
        'hours': _titles[i].$4,
        'stage': _titles[i].$5,
        'secret': 'HIDDEN-VALUE-123',
      },
    }, isReceived: false)!,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SvRig rig;
  late SmartViewController c;

  SvTable table() {
    final t = SvTable(sourceNamed('tickets'))
      ..rows.assignAll(_rows())
      ..phase.value = SvPhase.ready;
    return t;
  }

  void init() {
    Get.reset();
    rig = SvRig();
    Get.put<SmartViewRepository>(rig.repo);
    Get.put<TicketRepository>(rig.tickets);
    Get.put<SubmissionRepository>(_NoSubmissions());
    Get.put<FormFileRepository>(FakeFiles());
    Get.put<ConnectivityService>(_Connectivity());
    c = SmartViewController(
      repo: rig.repo,
      tickets: rig.tickets,
      submissions: Get.find<SubmissionRepository>(),
      prefs: SmartViewPrefs(),
      newTicketDetail: (id) => TicketDetailController(
        ticketId: id,
        tickets: rig.tickets,
        files: Get.find<FormFileRepository>(),
        connectivity: Get.find<ConnectivityService>(),
      ),
    );
    c.current.value = sourceNamed('tickets');
    c.table.value = table();
  }

  tearDown(() {
    rig.tickets.onClose();
    rig.repo.onClose();
    Get.reset();
  });

  void queryTest(String name, Future<void> Function(WidgetTester t) body) =>
      testWidgets(name, (tester) async {
        init();
        tester.view.physicalSize = const Size(390 * 2, 844 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          GetMaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: Colors.white,
              body: SmartViewContent(controller: c),
            ),
          ),
        );
        await pumpFor(tester, 300);
        await body(tester);
      });

  List<String> shownTitles() => [
    for (final r in c.shownRows) '${r.values['title']}',
  ];

  Finder header(String label) => find.descendant(
    of: find.byType(SmartViewTable),
    matching: find.text(label),
  );

  Future<void> openSearch(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.search).first);
    await pumpFor(t, 400);
  }

  Future<void> type(WidgetTester t, String text) async {
    await t.enterText(find.byType(TextField), text);
    await pumpFor(t, 400);
  }

  queryTest('search: typing waits 250 ms, then both lists follow', (t) async {
    expect(find.text('Router down'), findsOneWidget);
    await openSearch(t);
    await t.enterText(find.byType(TextField), 'router');
    await t.pump(const Duration(milliseconds: 100));
    expect(c.query.value.search, '');
    expect(find.text('Printer jammed'), findsOneWidget);
    await pumpFor(t, 300);
    expect(c.query.value.search, 'router');
    expect(find.text('Router down'), findsOneWidget);
    expect(find.text('Printer jammed'), findsNothing);
    c.mode.value = SvViewMode.table;
    await pumpFor(t, 500);
    expect(find.text('Router down'), findsOneWidget);
    expect(find.text('Printer jammed'), findsNothing);
  });

  queryTest('search limited to one field; the chip label follows', (t) async {
    await openSearch(t);
    expect(find.text('All fields'), findsOneWidget);
    await t.tap(find.text('All fields'));
    await pumpFor(t, 300);
    await t.tap(find.text('Area').last);
    await pumpFor(t, 400);
    expect(find.widgetWithText(SvPill, 'Area'), findsOneWidget);
    expect(c.query.value.scope, 'area');
    await type(t, 'billing');
    expect(shownTitles(), ['Router down', 'Alpha invoice']);
    await type(t, 'router');
    expect(shownTitles(), isEmpty);
    expect(find.text('No records match'), findsOneWidget);
  });

  queryTest('a hidden field is never searchable or offered', (t) async {
    await openSearch(t);
    await type(t, 'HIDDEN-VALUE');
    expect(c.shownRows, isEmpty);
    expect(find.text('No records match'), findsOneWidget);
    await t.tap(find.text('All fields'));
    await pumpFor(t, 300);
    expect(find.text('Secret'), findsNothing);
    expect(c.columns!.columns.where((x) => x.key == 'secret'), isEmpty);
  });

  queryTest('filter sheet: add a row, operators follow the field type, '
      'count updates, Apply keeps, closing discards', (t) async {
    await t.tap(find.byIcon(Icons.filter_list));
    await pumpFor(t, 800);
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('6 of 6 records'), findsOneWidget);
    await t.tap(find.text('Add filter'));
    await pumpFor(t, 400);
    // The first field is "No." (a number): number operators.
    await t.tap(find.text('=').first);
    await pumpFor(t, 300);
    for (final op in ['=', '≠', '>', '≥', '<', '≤', 'between', 'is empty']) {
      expect(find.text(op), findsWidgets, reason: op);
    }
    expect(find.text('contains'), findsNothing);
    await t.tapAt(const Offset(10, 300));
    await pumpFor(t, 300);
    // Switch the field to Title (text): text operators.
    await t.tap(
      find.descendant(
        of: find.byType(SvFilterSheetBody),
        matching: find.text('No.'),
      ),
    );
    await pumpFor(t, 300);
    await t.tap(find.text('Title').last);
    await pumpFor(t, 300);
    await t.tap(find.text('contains').first);
    await pumpFor(t, 300);
    for (final op in ['contains', 'is', 'is not', 'starts with']) {
      expect(find.text(op), findsWidgets, reason: op);
    }
    expect(find.text('≥'), findsNothing);
    await t.tapAt(const Offset(10, 300));
    await pumpFor(t, 300);
    await t.enterText(find.widgetWithText(TextField, 'Value'), 'a');
    await pumpFor(t, 300);
    expect(find.text('5 of 6 records'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Value'), 'alpha');
    await pumpFor(t, 300);
    expect(find.text('1 of 6 records'), findsOneWidget);
    // Not applied yet.
    expect(c.query.value.conditions, isEmpty);
    await t.tap(find.text('Apply'));
    await pumpFor(t, 800);
    expect(c.query.value.activeConditions.length, 1);
    expect(shownTitles(), ['Alpha invoice']);
    expect(find.text('Title contains alpha'), findsOneWidget);

    // Open again, add another row, close without Apply: nothing changes.
    await t.tap(find.byIcon(Icons.filter_list));
    await pumpFor(t, 800);
    await t.tap(find.text('Add filter'));
    await pumpFor(t, 400);
    await t.tapAt(const Offset(195, 20));
    await pumpFor(t, 800);
    expect(find.text('Filters'), findsNothing);
    expect(c.query.value.conditions.length, 1);
  });

  queryTest('a status field is picked from its distinct values', (t) async {
    c.setConditions(const [
      SvCondition('stage', 'in', ['Open']),
    ]);
    await pumpFor(t, 400);
    expect(shownTitles(), ['Printer jammed', 'Laptop request', 'Badge lost']);
    expect(find.text('Stage: Open'), findsOneWidget);
    await t.tap(find.byIcon(Icons.filter_list));
    await pumpFor(t, 800);
    expect(find.text('3 of 6 records'), findsOneWidget);
    await t.tap(find.text('In progress').last);
    await pumpFor(t, 300);
    expect(find.text('4 of 6 records'), findsOneWidget);
  });

  queryTest('chips: appear, tap the sort chip flips, x dismisses', (t) async {
    expect(find.text('Clear'), findsNothing);
    c.setConditions(const [SvCondition('hours', 'gte', '3')]);
    c.setSort('hours', isAscending: true);
    await pumpFor(t, 500);
    expect(find.text('Hours ≥ 3'), findsOneWidget);
    expect(find.text('Hours'), findsWidgets);
    expect(shownTitles(), [
      'Badge lost',
      'Router down',
      'Laptop request',
      'Zeta audit',
    ]);
    // Tap the sort chip: direction flips.
    await t.tap(find.widgetWithText(GestureDetector, 'Hours').first);
    await pumpFor(t, 400);
    expect(c.query.value.isAscending, isFalse);
    expect(shownTitles().first, 'Zeta audit');
    // Dismiss the filter chip.
    await t.tap(find.byIcon(Icons.close).first);
    await pumpFor(t, 400);
    expect(c.query.value.activeConditions, isEmpty);
    expect(find.text('Hours ≥ 3'), findsNothing);
    // Clear resets everything.
    await t.tap(find.text('Clear'));
    await pumpFor(t, 400);
    expect(c.query.value.isEmpty, isTrue);
  });

  queryTest('table header sort cycles asc, desc, none; cards follow', (
    t,
  ) async {
    c.mode.value = SvViewMode.table;
    await pumpFor(t, 500);
    await t.tap(header('No.'));
    await pumpFor(t, 300);
    expect(c.query.value.sortKey, '#no');
    expect(c.query.value.isAscending, isTrue);
    expect(shownTitles().first, 'Printer jammed');
    await t.tap(header('No.'));
    await pumpFor(t, 300);
    expect(c.query.value.isAscending, isFalse);
    expect(shownTitles().first, 'Zeta audit');
    await t.tap(header('No.'));
    await pumpFor(t, 300);
    expect(c.query.value.sortKey, isNull);
    expect(shownTitles().first, 'Printer jammed');
    // Cards use the same order.
    c.setSort('title', isAscending: true);
    c.mode.value = SvViewMode.cards;
    t.view.physicalSize = const Size(390 * 2, 3000 * 2);
    await pumpFor(t, 500);
    final ys = [
      for (final n in ['Alpha invoice', 'Badge lost', 'Laptop request'])
        t.getTopLeft(find.text(n)).dy,
    ];
    expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);
  });

  queryTest('footer note: only with more pages and an active query', (t) async {
    final tb = c.table.value!;
    tb.isPaging.value = true;
    await pumpFor(t, 200);
    expect(find.textContaining('loaded records'), findsNothing);
    c.setQuery(c.query.value.copyWith(search: 'zeta'));
    await pumpFor(t, 300);
    expect(
      find.text(
        'Showing results from 6 loaded records — load more to include the rest',
      ),
      findsOneWidget,
    );
    expect(find.text('Load more'), findsOneWidget);
    tb.isPaging.value = false;
    await pumpFor(t, 300);
    expect(find.textContaining('loaded records'), findsNothing);
    tb
      ..isCapped.value = true
      ..total.value = 9000;
    await pumpFor(t, 300);
    expect(find.textContaining('loaded records'), findsOneWidget);
  });

  queryTest('no match: a calm state with Clear filters', (t) async {
    c.setQuery(c.query.value.copyWith(search: 'zzzz'));
    await pumpFor(t, 400);
    expect(find.text('No records match'), findsOneWidget);
    expect(find.text('There is nothing here yet'), findsNothing);
    await t.tap(find.text('Clear filters'));
    await pumpFor(t, 400);
    expect(find.text('No records match'), findsNothing);
    expect(find.text('Router down'), findsOneWidget);
  });

  group('polish 2', () {
    BoxDecoration? borderOf(WidgetTester t, Finder inside) {
      final boxes = find
          .descendant(of: inside, matching: find.byType(DecoratedBox))
          .evaluate()
          .map((e) => (e.widget as DecoratedBox).decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.border != null);
      return boxes.isEmpty ? null : boxes.first;
    }

    queryTest('Add filter: the standard primary button, no gradient; with '
        'filters the secondary one', (t) async {
      await t.tap(find.byIcon(Icons.filter_list));
      await pumpFor(t, 800);
      final add = find.widgetWithText(AppButton, 'Add filter');
      expect(add, findsOneWidget);
      expect(
        find.descendant(of: add, matching: find.byType(AppBubbleSurface)),
        findsOneWidget,
      );
      final gradients = find
          .descendant(of: add, matching: find.byType(DecoratedBox))
          .evaluate()
          .map((e) => (e.widget as DecoratedBox).decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.gradient != null);
      expect(gradients, isEmpty);
      expect(
        find.descendant(of: add, matching: find.byIcon(Icons.add)),
        findsOneWidget,
      );
      await t.tap(add);
      await pumpFor(t, 400);
      final again = find.widgetWithText(AppButton, 'Add filter');
      expect(
        find.descendant(of: again, matching: find.byType(AppBubbleSurface)),
        findsNothing,
      );
    });

    queryTest('search field, scope chip and close use the standard border', (
      t,
    ) async {
      await openSearch(t);
      final field = find.byType(AppTextField);
      final d = borderOf(t, field)!;
      final focused = (d.border! as Border).top;
      expect(d.borderRadius, AppRadius.controlAll);
      FocusManager.instance.primaryFocus?.unfocus();
      await pumpFor(t, 300);
      final rest = (borderOf(t, field)!.border! as Border).top;
      expect(rest.color, AppColors.inputBorder);
      expect(rest.width, 1);
      // the app's own default field, focused and at rest
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppTextField(hint: 'x', autofocus: true)),
        ),
      );
      await pumpFor(t, 300);
      final std = borderOf(t, find.byType(AppTextField))!;
      expect((std.border! as Border).top.color, focused.color);
      expect((std.border! as Border).top.width, focused.width);
      expect(std.borderRadius, d.borderRadius);
      FocusManager.instance.primaryFocus?.unfocus();
      await pumpFor(t, 300);
      final stdRest =
          (borderOf(t, find.byType(AppTextField))!.border! as Border).top;
      expect(stdRest.color, rest.color);
      expect(stdRest.width, rest.width);
    });

    queryTest('the scope chip and the close button have the hairline too', (
      t,
    ) async {
      await openSearch(t);
      final chip = borderOf(t, find.byType(SvPill))!;
      expect((chip.border! as Border).top.color, AppColors.inputBorder);
      expect(chip.borderRadius, AppRadius.controlAll);
      final close = find.bySemanticsLabel('Close search');
      final box = t
          .widgetList<Container>(
            find.descendant(of: close, matching: find.byType(Container)),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect((box.border! as Border).top.color, AppColors.inputBorder);
      expect(box.borderRadius, AppRadius.controlAll);
    });
  });

  group('goldens', () {
    queryTest('golden: the filter sheet with two rows', (t) async {
      c.setConditions(const [
        SvCondition('title', 'contains', 'a'),
        SvCondition('stage', 'in', ['Open', 'Closed']),
      ]);
      await t.tap(find.byIcon(Icons.filter_list));
      await pumpFor(t, 900);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_filter_sheet.png'),
      );
    });

    queryTest('golden: the controls row with chips', (t) async {
      c.setConditions(const [
        SvCondition('title', 'contains', 'a'),
        SvCondition('stage', 'in', ['Open', 'Closed']),
      ]);
      c.setSort('hours', isAscending: false);
      await pumpFor(t, 600);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_controls_chips.png'),
      );
    });

    queryTest('golden: search expanded', (t) async {
      await openSearch(t);
      await type(t, 'router');
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_search_expanded.png'),
      );
    });

    queryTest('golden: the controls row at rest', (t) async {
      await pumpFor(t, 300);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_controls_rest.png'),
      );
    });

    queryTest('golden: the filter sheet with no filters', (t) async {
      await t.tap(find.byIcon(Icons.filter_list));
      await pumpFor(t, 900);
      expect(find.text('No filters yet'), findsOneWidget);
      expect(find.text('Add one to narrow the list'), findsOneWidget);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_filter_empty.png'),
      );
    });

    queryTest('golden: the sort sheet', (t) async {
      c.setSort('hours', isAscending: false);
      await pumpFor(t, 300);
      await t.tap(find.byIcon(Icons.swap_vert));
      await pumpFor(t, 900);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_sort_sheet.png'),
      );
    });

    queryTest('golden: no records match', (t) async {
      c.setQuery(c.query.value.copyWith(search: 'zzzz'));
      await pumpFor(t, 500);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_no_match.png'),
      );
    });
  });

  queryTest('the three buttons are 40 dp circles in a 48 dp tap box, tinted '
      'differently, and press scales them down', (t) async {
    for (final icon in [Icons.search, Icons.filter_list, Icons.swap_vert]) {
      final box = t.getSize(
        find
            .ancestor(of: find.byIcon(icon), matching: find.byType(SizedBox))
            .first,
      );
      expect(box.height, greaterThanOrEqualTo(48));
    }
    final fills = [
      for (final icon in [Icons.search, Icons.filter_list, Icons.swap_vert])
        (t
                    .widget<AnimatedContainer>(
                      find
                          .ancestor(
                            of: find.byIcon(icon),
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .color,
    ];
    expect(fills.toSet().length, 3);
    for (final f in fills) {
      expect(f!.a, closeTo(0.11, 0.01));
    }
    final gesture = await t.startGesture(
      t.getCenter(find.byIcon(Icons.search)),
    );
    await pumpFor(t, 200);
    expect(
      t.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale,
      0.94,
    );
    await gesture.up();
    await pumpFor(t, 300);
    c.setQuery(c.query.value.copyWith(search: 'a'));
    await pumpFor(t, 300);
    final active =
        (t
                    .widget<AnimatedContainer>(
                      find
                          .ancestor(
                            of: find.byIcon(Icons.search),
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .color!;
    expect(active.a, closeTo(0.20, 0.01));
  });

  test('the query is kept per view and restored', () async {
    init();
    rig.socket.answers['submissions.list'] = listPager([ownRow(1)]);
    rig.socket.answers['records.mine'] = minePager({'with': []});
    final a = sourceNamed('tickets');
    final b = realSources().firstWhere((s) => s.name != 'tickets');
    c.table.value = null;
    c.current.value = null;
    await c.show(a);
    c.setQuery(c.query.value.copyWith(search: 'x'));
    c.setSort('title', isAscending: false);
    await c.show(b);
    expect(c.query.value.isEmpty, isTrue);
    c.setConditions(const [SvCondition('title', 'filled')]);
    await c.show(a);
    expect(c.query.value.search, 'x');
    expect(c.query.value.sortKey, 'title');
    expect(c.query.value.isAscending, isFalse);
    expect(c.searchField.text, 'x');
    expect(c.isSearchOpen.value, isTrue);
    await c.show(b);
    expect(c.query.value.conditions.length, 1);
    c.clearQuery();
    await c.show(a);
    expect(c.query.value.search, 'x');
    await c.show(b);
    expect(c.query.value.isEmpty, isTrue);
  });

  test('the source rows are never changed by a query', () {
    init();
    final before = [for (final r in c.table.value!.rows) r.id];
    c.setSort('hours', isAscending: false);
    c.setQuery(c.query.value.copyWith(search: 'a'));
    c.shownRows;
    expect([for (final r in c.table.value!.rows) r.id], before);
  });

  test('the filter sheet is exported for the debug route', () {
    expect(SvFilterSheet.show, isNotNull);
  });
}

class _NoSubmissions extends GetxService implements SubmissionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
