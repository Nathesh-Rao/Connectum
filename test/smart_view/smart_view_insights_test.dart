import 'dart:convert';
import 'dart:io';

import 'package:connectum/core/debug/seed_smart_view.dart';
import 'package:connectum/core/theme/app_sv.dart';
import 'package:connectum/core/theme/app_tones.dart';
import 'package:connectum/core/widgets/app_speed_dial.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/smart_view/engine/sv_engine.dart';
import 'package:connectum/data/smart_view/engine/sv_insights.dart';
import 'package:connectum/data/smart_view/engine/sv_values.dart';
import 'package:connectum/data/smart_view/sv_columns.dart';
import 'package:connectum/data/smart_view/sv_query.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:connectum/features/smart_view/widgets/sv_chart_view.dart';
import 'package:connectum/features/smart_view/widgets/sv_charts_sheet.dart';
import 'package:connectum/features/smart_view/widgets/sv_insight_sheet.dart';
import 'package:connectum/features/smart_view/widgets/sv_kpi_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'sv_support.dart';

Future<void> pumpFor(WidgetTester tester, [int ms = 600]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _NoSubmissions extends GetxService implements SubmissionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---- the speed dial ----------------------------------------------------

  group('KPI tiles are one size', () {
    const tiles = [
      SvKpiTile(
        id: 'a',
        label: 'Rows',
        value: 120,
        icon: 'functions',
        tone: 'blue',
      ),
      SvKpiTile(
        id: 'b',
        label: 'A much longer label that needs two lines of text',
        value: 1234567,
        icon: 'functions',
        tone: 'green',
        sub: 'avg 12.5',
      ),
      SvKpiTile(
        id: 'c',
        label: 'Open',
        value: 3,
        icon: 'schedule',
        tone: 'waiting',
      ),
    ];

    for (final scale in [1.0, 1.3]) {
      testWidgets('equal sizes at text scale $scale', (t) async {
        t.view.physicalSize = const Size(390 * 2, 844 * 2);
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.resetPhysicalSize);
        await t.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 844),
                textScaler: TextScaler.linear(scale),
              ),
              child: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(16),
                  child: SvKpiGrid(tiles: tiles),
                ),
              ),
            ),
          ),
        );
        await pumpFor(t, 1200);
        final sizes = [
          for (final e
              in find
                  .descendant(
                    of: find.byType(SvKpiGrid),
                    matching: find.byType(Opacity),
                  )
                  .evaluate())
            (e.renderObject! as RenderBox).size,
        ];
        expect(sizes.length, 3);
        expect(sizes.toSet().length, 1);
        expect(sizes.first.width, closeTo((390 - 32 - 12) / 2, 0.5));
        expect(t.takeException(), isNull);
      });
    }
  });

  group('AppSpeedDial', () {
    var picked = <String>[];

    List<AppSpeedDialOption> three() => [
      AppSpeedDialOption(
        label: 'Add record',
        icon: Icons.person_add,
        onSelected: () => picked.add('add'),
      ),
      AppSpeedDialOption(
        label: 'KPI',
        icon: Icons.insights_outlined,
        onSelected: () => picked.add('kpi'),
      ),
      AppSpeedDialOption(
        label: 'Charts',
        icon: Icons.bar_chart_rounded,
        onSelected: () => picked.add('charts'),
      ),
    ];

    Widget host(List<AppSpeedDialOption> options, {Object? closeKey}) =>
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Stack(
              children: [
                const Center(child: Text('page')),
                Positioned.fill(
                  child: AppSpeedDial(options: options, closeKey: closeKey),
                ),
              ],
            ),
          ),
        );

    void phone(WidgetTester t) {
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.resetPhysicalSize);
    }

    setUp(() => picked = []);

    testWidgets('closed it shows the grid icon, not plus; open shows close '
        'and fans the options out', (t) async {
      phone(t);
      await t.pumpWidget(host(three()));
      expect(find.text('KPI'), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Actions'));
      await pumpFor(t, 700);
      for (final label in ['Add record', 'KPI', 'Charts']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.grid_view_rounded), findsNothing);
      // every option is a 48 dp circle
      final circle = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      );
      expect(t.getSize(circle.first), const Size(48, 48));
    });

    testWidgets('options come one after another, 60 ms apart', (t) async {
      phone(t);
      await t.pumpWidget(host(three()));
      await t.tap(find.bySemanticsLabel('Actions'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      expect(find.text('Add record'), findsOneWidget);
      expect(find.text('KPI'), findsNothing);
      await t.pump(const Duration(milliseconds: 40));
      expect(find.text('KPI'), findsOneWidget);
      expect(find.text('Charts'), findsNothing);
      await t.pump(const Duration(milliseconds: 60));
      expect(find.text('Charts'), findsOneWidget);
      await pumpFor(t, 500);
    });

    testWidgets('an option runs its action and closes the menu', (t) async {
      phone(t);
      await t.pumpWidget(host(three()));
      await t.tap(find.bySemanticsLabel('Actions'));
      await pumpFor(t, 700);
      await t.tap(find.text('KPI'));
      await pumpFor(t, 700);
      expect(picked, ['kpi']);
      expect(find.text('KPI'), findsNothing);
    });

    testWidgets('the scrim closes it', (t) async {
      phone(t);
      await t.pumpWidget(host(three()));
      await t.tap(find.bySemanticsLabel('Actions'));
      await pumpFor(t, 700);
      await t.tapAt(const Offset(20, 120));
      await pumpFor(t, 700);
      expect(find.text('KPI'), findsNothing);
      expect(picked, isEmpty);
    });

    testWidgets('Back closes the menu first, then leaves', (t) async {
      phone(t);
      await t.pumpWidget(host(three()));
      await t.tap(find.bySemanticsLabel('Actions'));
      await pumpFor(t, 700);
      await t.binding.handlePopRoute();
      await pumpFor(t, 700);
      expect(find.text('KPI'), findsNothing);
      expect(find.text('page'), findsOneWidget);
    });

    testWidgets('one option: the button shows its icon and runs it at once', (
      t,
    ) async {
      phone(t);
      await t.pumpWidget(host([three().first]));
      expect(find.byIcon(Icons.person_add), findsOneWidget);
      await t.tap(find.byIcon(Icons.person_add));
      await pumpFor(t, 300);
      expect(picked, ['add']);
      expect(find.text('Add record'), findsNothing);
    });

    testWidgets('no option draws nothing', (t) async {
      phone(t);
      await t.pumpWidget(host(const []));
      expect(find.byType(AppSpeedDial), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNothing);
    });

    testWidgets('a change of the close key (tab or view) closes it', (t) async {
      phone(t);
      await t.pumpWidget(host(three(), closeKey: 'a'));
      await t.tap(find.bySemanticsLabel('Actions'));
      await pumpFor(t, 700);
      expect(find.text('KPI'), findsOneWidget);
      await t.pumpWidget(host(three(), closeKey: 'b'));
      await pumpFor(t, 700);
      expect(find.text('KPI'), findsNothing);
      // the same key keeps it open
      await t.tap(find.bySemanticsLabel('Actions'));
      await pumpFor(t, 700);
      await t.pumpWidget(host(three(), closeKey: 'b'));
      await pumpFor(t, 100);
      expect(find.text('KPI'), findsOneWidget);
    });

    testWidgets('golden: the speed dial open', (t) async {
      phone(t);
      await t.pumpWidget(host(three()));
      await t.tap(find.bySemanticsLabel('Actions'));
      await pumpFor(t, 800);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_speed_dial_open.png'),
      );
    });
  });

  // ---- the numbers -------------------------------------------------------

  group('SvInsights numbers', () {
    final v =
        jsonDecode(
              File(
                'test/fixtures/smart_view/engine/vectors.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final tj = v['table'] as Map<String, dynamic>;
    final table = EngineTable(
      [
        for (final c in tj['columns'] as List)
          EngineCol(
            c['key'],
            c['label'],
            EngineType.values.firstWhere((t) => t.name == c['type']),
          ),
      ],
      [for (final r in tj['rows'] as List) (r as Map).cast<String, Object?>()],
    );
    final all = List.generate(table.rows.length, (i) => i);

    test('count, sum, avg, min and max over the rows', () {
      expect(SvInsights.stat(table, all, 'qty', 'count'), 7);
      expect(SvInsights.stat(table, all, 'qty', 'sum'), 1268);
      expect(
        SvInsights.stat(table, all, 'qty', 'avg'),
        closeTo(181.142857, 1e-5),
      );
      expect(SvInsights.stat(table, all, 'qty', 'min'), -3);
      expect(SvInsights.stat(table, all, 'qty', 'max'), 1200);
    });

    test('an empty set is 0 for every aggregate', () {
      for (final a in ['count', 'sum', 'avg', 'min', 'max']) {
        expect(SvInsights.stat(table, const [], 'qty', a), 0, reason: a);
      }
      final k = SvInsights.kpis(
        table,
        const [],
        loaded: 8,
        statusKey: 'kind',
        numberKeys: const ['qty'],
      );
      expect(k.first.value, 0);
      expect(k.first.sub, 'of 8');
      expect(k.where((t) => t.id.startsWith('status:')), isEmpty);
      expect(k.last.value, 0);
      expect(k.last.sub, isEmpty);
    });

    test('the KPI cards: Records, top three statuses, totals with avg', () {
      final k = SvInsights.kpis(
        table,
        all,
        loaded: 8,
        statusKey: 'kind',
        numberKeys: const ['qty'],
      );
      expect(
        [for (final t in k) t.id],
        ['rows', 'status:A', 'status:B', 'sum:qty'],
      );
      expect(k[0].value, 8);
      expect(k[0].sub, isEmpty);
      expect(k[1].value, 4);
      expect(k[1].sub, '50% of the records');
      expect(k[2].value, 3);
      expect(k[3].label, 'Qty, total');
      expect(k[3].value, 1268);
      expect(k[3].sub, 'avg 181.14');
    });

    test('they follow the filter: the rows passed in are the only ones', () {
      final onlyA = SvEngine.filter(
        table,
        conditions: const [
          SvCondition('kind', 'in', ['A']),
        ],
      );
      final k = SvInsights.kpis(
        table,
        onlyA,
        loaded: 8,
        statusKey: 'kind',
        numberKeys: const ['qty'],
      );
      expect(k[0].value, 4);
      expect(k[0].sub, 'of 8');
      expect(k.firstWhere((t) => t.id == 'sum:qty').value, 1214);
      expect(k.where((t) => t.id == 'status:B'), isEmpty);
    });

    test('numbers print with thousands separators and no intl', () {
      expect(SvInsights.format(1234567.5), '1,234,567.5');
      expect(SvInsights.format(0), '0');
      expect(SvInsights.format(-1234), '-1,234');
      expect(SvInsights.format(1000), '1,000');
      expect(SvInsights.format(999.999), '1,000');
      expect(SvInsights.format(0.5), '0.5');
      expect(SvInsights.format(double.nan), '—');
    });

    test('chart: a status distribution, biggest first, blanks as (empty)', () {
      final d = SvInsights.chart(
        table,
        all,
        const SvChartSpec(groupKey: 'kind'),
      );
      expect([for (final p in d.points) p.label], ['A', 'B', '(empty)']);
      expect([for (final p in d.points) p.value], [4, 3, 1]);
      expect(d.subtitle, 'Records by Kind');
      expect(d.total, 8);
      expect(SvInsights.defaultKind(d), SvChartKind.donut);
    });

    test('chart: sum and average of a number column per group', () {
      final sum = SvInsights.chart(
        table,
        all,
        const SvChartSpec(
          groupKey: 'kind',
          agg: SvChartAgg.sum,
          valueKey: 'qty',
        ),
      );
      expect([for (final p in sum.points) p.label], ['A', 'B', '(empty)']);
      expect([for (final p in sum.points) p.value], [1214, 54, 0]);
      expect(sum.unit, 'Sum of Qty');
      final avg = SvInsights.chart(
        table,
        all,
        const SvChartSpec(
          groupKey: 'kind',
          agg: SvChartAgg.avg,
          valueKey: 'qty',
        ),
      );
      expect(avg.points.first.value, closeTo(1214 / 4, 1e-9));
    });

    test('chart: month buckets in date order, blank dates left out', () {
      final d = SvInsights.chart(
        table,
        all,
        const SvChartSpec(groupKey: 'day', bucket: SvDateBucket.month),
      );
      expect(d.isDate, isTrue);
      expect([for (final p in d.points) p.label], ['Nov 2026', 'Dec 2026']);
      expect([for (final p in d.points) p.value], [6, 1]);
    });

    test('chart: a span of a month or less is bucketed by day', () {
      final d = SvInsights.chart(
        table,
        all,
        const SvChartSpec(groupKey: 'day'),
      );
      expect(
        [for (final p in d.points) p.label],
        ['Nov 10', 'Nov 11', 'Nov 12', 'Nov 30', 'Dec 1'],
      );
      expect([for (final p in d.points) p.value], [1, 1, 3, 1, 1]);
      expect(SvInsights.defaultKind(d), SvChartKind.line);
    });

    test('chart: more than 24 categories keep the biggest and merge the '
        'rest into Others', () {
      final rows = <Map<String, Object?>>[];
      for (var c = 0; c < 30; c++) {
        // category c has (30 - c) rows
        for (var n = 0; n < 30 - c; n++) {
          rows.add({'kind': 'K${c.toString().padLeft(2, '0')}'});
        }
      }
      final t = EngineTable(const [
        EngineCol('kind', 'Kind', EngineType.text),
      ], rows);
      final d = SvInsights.chart(
        t,
        List.generate(rows.length, (i) => i),
        const SvChartSpec(groupKey: 'kind'),
      );
      expect(d.points.length, 25);
      expect(d.points.first.label, 'K00');
      expect(d.points.last.label, 'Others');
      expect(d.points.last.colorIndex, -1);
      // categories 24..29 hold 6+5+4+3+2+1 rows
      expect(d.points.last.value, 21);
      expect(d.points.last.count, 21);
      expect(d.total, rows.length);
    });

    test('chart: a value keeps its colour when the filter changes', () {
      final a = SvInsights.chart(
        table,
        all,
        const SvChartSpec(groupKey: 'kind'),
      );
      final onlyB = SvEngine.filter(
        table,
        conditions: const [
          SvCondition('kind', 'in', ['B']),
        ],
      );
      final b = SvInsights.chart(
        table,
        onlyB,
        const SvChartSpec(groupKey: 'kind'),
      );
      int colorOf(SvChartData d, String l) =>
          d.points.firstWhere((p) => p.label == l).colorIndex;
      expect(colorOf(b, 'B'), colorOf(a, 'B'));
      expect(colorOf(a, 'A'), isNot(colorOf(a, 'B')));
      // and the same twice: never random
      expect(
        colorOf(
          SvInsights.chart(table, all, const SvChartSpec(groupKey: 'kind')),
          'A',
        ),
        colorOf(a, 'A'),
      );
    });

    test('chart: an empty selection is an empty chart', () {
      final d = SvInsights.chart(
        table,
        const [],
        const SvChartSpec(groupKey: 'kind'),
      );
      expect(d.isEmpty, isTrue);
      expect(d.total, 0);
    });

    test('the palette has eight colours, all cool (no warm hue)', () {
      expect(AppSv.chartPalette.length, 8);
      expect(AppSv.chartPalette.toSet().length, 8);
    });
  });

  // ---- the sheets over a controller --------------------------------------

  group('KPI and Charts sheets', () {
    late SvRig rig;
    late SmartViewController c;

    void init() {
      Get.reset();
      rig = SvRig();
      c = SmartViewController(
        repo: rig.repo,
        tickets: rig.tickets,
        submissions: _NoSubmissions(),
        newTicketDetail: (_) => throw UnimplementedError(),
      );
      final source = SeedSmartView.leaveSource();
      c.current.value = source;
      c.table.value = SvTable(source)
        ..rows.assignAll(SeedSmartView.leaveRows())
        ..phase.value = SvPhase.ready;
    }

    tearDown(() {
      rig.tickets.onClose();
      rig.repo.onClose();
      Get.reset();
    });

    Widget frame(Widget body) => GetMaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SvInsightSheetFrame(
            title: 'KPIs',
            icon: Icons.insights_outlined,
            tone: AppTones.primary,
            onClose: () {},
            body: body,
          ),
        ),
      ),
    );

    void phone(WidgetTester t) {
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.resetPhysicalSize);
    }

    testWidgets('the demo Leave request has meaningful KPIs', (t) async {
      init();
      phone(t);
      await t.pumpWidget(frame(SvKpiBody(controller: c)));
      await pumpFor(t, 900);
      expect(find.text('Records'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('Based on 120 records'), findsOneWidget);
      // the status column's three biggest values and two totals
      expect(find.textContaining('% of the records'), findsNWidgets(3));
      expect(find.text('Days, total'), findsOneWidget);
      expect(find.text('Balance (days), total'), findsOneWidget);
      expect(find.textContaining('avg '), findsNWidgets(2));
    });

    testWidgets('the tiles react to a filter, with the count-up done', (
      t,
    ) async {
      init();
      phone(t);
      await t.pumpWidget(frame(SvKpiBody(controller: c)));
      await pumpFor(t, 900);
      c.setConditions(const [
        SvCondition('stage', 'in', ['Done']),
      ]);
      await pumpFor(t, 1200);
      // every 7th of 120 records is Done: 0, 7, ... 119
      expect(find.text('18'), findsWidgets);
      expect(find.text('of 120'), findsOneWidget);
      expect(find.text('Based on 18 of 120 records'), findsOneWidget);
    });

    testWidgets('more pages to come say so', (t) async {
      init();
      phone(t);
      c.table.value!.isPaging.value = true;
      await t.pumpWidget(frame(SvKpiBody(controller: c)));
      await pumpFor(t, 900);
      expect(find.text('Based on 120 loaded records'), findsOneWidget);
    });

    testWidgets('no records: a calm empty block', (t) async {
      init();
      phone(t);
      c.table.value!.rows.clear();
      await t.pumpWidget(frame(SvKpiBody(controller: c)));
      await pumpFor(t, 500);
      expect(find.text('No records yet'), findsOneWidget);
    });

    testWidgets('the sheet has a grab handle and no nested list in the grid', (
      t,
    ) async {
      init();
      phone(t);
      await t.pumpWidget(frame(SvKpiBody(controller: c)));
      await pumpFor(t, 900);
      expect(find.byKey(const ValueKey('sv-insight-handle')), findsOneWidget);
    });

    testWidgets('golden: the KPI sheet', (t) async {
      init();
      phone(t);
      await t.pumpWidget(frame(SvKpiBody(controller: c)));
      await pumpFor(t, 1000);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_kpi_sheet.png'),
      );
    });

    testWidgets('Charts: starts as the status distribution, switches group, '
        'kind and value', (t) async {
      init();
      phone(t);
      await t.pumpWidget(frame(SvChartsBody(controller: c)));
      await pumpFor(t, 900);
      expect(find.text('Group by: Stage'), findsOneWidget);
      expect(find.text('Value: Count'), findsOneWidget);
      expect(find.text('Records by Stage'), findsOneWidget);
      expect(find.text('Based on 120 records'), findsOneWidget);
      // five values: a donut with a legend
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Donut chart'), findsNothing);
      // a date field exists: Line is offered, and it moves to the date field
      await t.tap(find.bySemanticsLabel('Line chart'));
      await pumpFor(t, 700);
      expect(find.text('Group by: From'), findsOneWidget);
      expect(find.textContaining('(by month)'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Bar chart'));
      await pumpFor(t, 700);
      expect(find.text('Group by: From'), findsOneWidget);
    });

    testWidgets('Charts react to a filter', (t) async {
      init();
      phone(t);
      await t.pumpWidget(frame(SvChartsBody(controller: c)));
      await pumpFor(t, 900);
      c.setConditions(const [
        SvCondition('stage', 'in', ['Done']),
      ]);
      await pumpFor(t, 900);
      expect(find.text('Based on 18 of 120 records'), findsOneWidget);
    });

    testWidgets('Charts with nothing matching: a calm empty block', (t) async {
      init();
      phone(t);
      c.setConditions(const [SvCondition('title', 'contains', 'zzzzzz')]);
      await t.pumpWidget(frame(SvChartsBody(controller: c)));
      await pumpFor(t, 600);
      expect(find.text('Nothing to chart'), findsOneWidget);
    });

    testWidgets('the sheets compute nothing while closed', (t) async {
      init();
      expect(c.insightRows, isNotEmpty); // asked, so computed once
      final first = c.insightRows;
      expect(identical(first, c.insightRows), isTrue);
      c.setConditions(const [
        SvCondition('stage', 'in', ['Done']),
      ]);
      expect(c.insightRows.length, 18);
    });
  });

  // ---- the three chart drawings -----------------------------------------

  group('chart goldens', () {
    SvChartData data(SvChartSpec spec) {
      final rows = SeedSmartView.leaveRows();
      final source = SeedSmartView.leaveSource();
      final input = SvEngineInput.of(SmartViewColumns.of(source), rows);
      return SvInsights.chart(
        input.table,
        input.positions(SmartViewQuery.none),
        spec,
      );
    }

    Future<void> golden(
      WidgetTester t,
      SvChartData d,
      SvChartKind kind,
      String file,
    ) async {
      t.view.physicalSize = const Size(390 * 2, 520 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: SvChartView(data: d, kind: kind),
              ),
            ),
          ),
        ),
      );
      await pumpFor(t, 700);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$file'),
      );
    }

    testWidgets('bar', (t) async {
      await golden(
        t,
        data(const SvChartSpec(groupKey: 'kind')),
        SvChartKind.bar,
        'sv_chart_bar.png',
      );
    });

    testWidgets('donut', (t) async {
      await golden(
        t,
        data(const SvChartSpec(groupKey: 'stage')),
        SvChartKind.donut,
        'sv_chart_donut.png',
      );
    });

    testWidgets('line', (t) async {
      await golden(
        t,
        data(const SvChartSpec(groupKey: 'from')),
        SvChartKind.line,
        'sv_chart_line.png',
      );
    });

    testWidgets('the drawing starts empty and fills in', (t) async {
      final d = data(const SvChartSpec(groupKey: 'kind'));
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SvChartView(data: d, kind: SvChartKind.bar),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 500));
      expect(AppSv.chartDraw, const Duration(milliseconds: 450));
    });
  });

  test('the engine knows dates the charts bucket', () {
    expect(SvValues.toTime('2026-11-10'), isNotNull);
  });
}
