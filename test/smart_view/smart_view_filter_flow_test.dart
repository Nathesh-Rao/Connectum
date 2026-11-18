import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/smart_view/engine/sv_engine.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/models/sv_source.dart';
import 'package:connectum/data/smart_view/sv_prefs.dart';
import 'package:connectum/data/smart_view/sv_query.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:connectum/features/smart_view/smart_view_view.dart';
import 'package:connectum/features/smart_view/widgets/sv_filter_draft.dart';
import 'package:connectum/features/smart_view/widgets/sv_filter_sheet.dart';
import 'package:connectum/features/tickets/ticket_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';
import 'sv_support.dart';

// Fakes only: no server, no phone. DevGuard is for the integration tests
// against the BE dev machine; nothing here opens a socket to anywhere.

class _Connectivity extends ConnectivityService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {
    state.value = AppConnectivity.online;
  }

  @override
  void attachSocket(Rx<SocketState> socketState) {}
}

class _NoSubmissions extends GetxService implements SubmissionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> pumpMicro() => Future<void>.delayed(Duration.zero);

Future<void> pumpFor(WidgetTester tester, [int ms = 600]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

SvSource _source(String name) => SvSource.tryParse({
  'name': name,
  'caption': name,
  'owner': 'svcapcpw1ann',
  'status': {
    'field': 'stage',
    'final': ['Closed'],
    'statuses': ['Open', 'In progress', 'Closed'],
  },
  'fields': [
    {'caption': 'Title', 'name': 'title', 'type': 'text'},
    {'caption': 'Stage', 'name': 'stage', 'type': 'list'},
    {'caption': 'Due', 'name': 'due', 'type': 'date'},
    {'caption': 'Hours', 'name': 'hours', 'type': 'number'},
    {'caption': 'Urgent', 'name': 'urgent', 'type': 'toggle'},
  ],
})!;

const _data = [
  ('Printer jammed', 'Open', '2026-11-20', 2.5, true),
  ('Router down', 'In progress', '2026-10-02', 4, false),
  ('Alpha invoice', 'Closed', '', 1, false),
  ('Laptop request', 'Open', '2026-12-05', 8, true),
  ('Badge lost', 'Open', '2026-11-02', 3, false),
  ('Zeta audit', 'Closed', '2026-11-30', 12, true),
];

List<SvRow> _rows(String tstruct, {int offset = 0}) => [
  for (var i = 0; i < _data.length; i++)
    SvRow.tryParse({
      'id': offset + i + 1,
      'by': 'svcapcpw1ann',
      'byName': 'Ann Rao',
      'ts': 1794833216000 + i * 60000,
      'tstruct': tstruct,
      'canEdit': true,
      'values': {
        'title': _data[i].$1,
        'stage': _data[i].$2,
        'due': _data[i].$3,
        'hours': _data[i].$4,
        'urgent': _data[i].$5,
      },
    }, isReceived: false)!,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SvRig rig;
  late SmartViewController c;

  SvTable tableOf(String name, {int offset = 0}) => SvTable(_source(name))
    ..rows.assignAll(_rows(name, offset: offset))
    ..phase.value = SvPhase.ready;

  setUp(() {
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
    c.current.value = _source('tickets');
    c.table.value = tableOf('tickets');
  });

  tearDown(() {
    rig.tickets.onClose();
    rig.repo.onClose();
    Get.reset();
  });

  List<String> titles() => [
    for (final r in c.shownRows) '${r.values['title']}',
  ];

  /// What the sheet does: a draft on the controller's input and query, edited,
  /// then Apply = `setConditions(draft.conditions)`.
  SvFilterDraft draft() => SvFilterDraft(c.engineInput!, c.query.value);

  void apply(SvFilterDraft d) => c.setConditions(d.conditions);

  int addRow(SvFilterDraft d, String col, String op, [Object? value]) {
    d.add();
    final id = d.rows.last.id;
    d.setCol(id, d.colOf(col)!);
    d.setOp(id, op);
    if (value != null) d.setValue(id, value);
    return id;
  }

  group('through the real controller', () {
    test('add a filter, Apply: rows and chips change; reopen, remove, Apply: '
        'back to unfiltered', () {
      expect(titles().length, 6);
      final d = draft();
      addRow(d, 'title', 'contains', 'alpha');
      expect(d.count, 1);
      // Not applied yet.
      expect(titles().length, 6);
      apply(d);
      expect(titles(), ['Alpha invoice']);
      expect(c.query.value.activeConditions.length, 1);

      final again = draft();
      expect(again.rows.length, 1);
      again.remove(again.rows.first.id);
      expect(again.count, 6);
      // Not applied yet: the main screen still filtered.
      expect(titles(), ['Alpha invoice']);
      apply(again);
      expect(titles().length, 6);
      expect(c.query.value.conditions, isEmpty);
      expect(c.query.value.activeConditions, isEmpty);
    });

    test('Clear all in the sheet clears the draft only; Clear in the chips '
        'strip clears the committed query', () {
      apply(draft()..add());
      c.setConditions(const [SvCondition('title', 'contains', 'a')]);
      final d = draft();
      expect(d.rows.length, 1);
      d.clear();
      expect(d.rows, isEmpty);
      expect(c.query.value.conditions.length, 1);
      c.clearQuery();
      expect(c.query.value.isEmpty, isTrue);
      expect(titles().length, 6);
    });

    test('closing the sheet without Apply discards the draft', () {
      final d = draft();
      addRow(d, 'title', 'contains', 'alpha');
      expect(c.query.value.conditions, isEmpty);
      expect(titles().length, 6);
    });

    test('Apply replaces: a removed row is gone, an edited one is the new '
        'value', () {
      c.setConditions(const [
        SvCondition('title', 'contains', 'a'),
        SvCondition('stage', 'in', ['Open']),
      ]);
      final d = draft();
      d.remove(d.rows.first.id);
      apply(d);
      expect(c.query.value.conditions, const [
        SvCondition('stage', 'in', ['Open']),
      ]);
      final e = draft();
      e.setValue(e.rows.first.id, ['Closed']);
      apply(e);
      expect(titles(), ['Alpha invoice', 'Zeta audit']);
    });

    test('a different value of the same filter gives a different result', () {
      c.setConditions(const [SvCondition('title', 'contains', 'alpha')]);
      expect(titles(), ['Alpha invoice']);
      c.setConditions(const [SvCondition('title', 'contains', 'zeta')]);
      expect(titles(), ['Zeta audit']);
      // The very same list object mutated and re-assigned.
      final list = <SvCondition>[const SvCondition('title', 'contains', 'x')];
      c.setConditions(list);
      final before = titles();
      list[0] = const SvCondition('title', 'contains', 'router');
      c.setConditions(List.of(list));
      expect(before, isNot(titles()));
      expect(titles(), ['Router down']);
    });
  });

  group('the cache key', () {
    test('equal queries are equal with the same hash; different ones are '
        'not', () {
      const a = SmartViewQuery(
        conditions: [
          SvCondition('stage', 'in', ['Open', 'Closed']),
        ],
      );
      const b = SmartViewQuery(
        conditions: [
          SvCondition('stage', 'in', ['Open', 'Closed']),
        ],
      );
      const other = SmartViewQuery(
        conditions: [
          SvCondition('stage', 'in', ['Open']),
        ],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(other));
      expect(a, isNot(a.copyWith(search: 'x')));
      expect(a, isNot(a.copyWith(scope: () => 'title')));
      expect(a, isNot(a.copyWith(sortKey: () => 'hours')));
      expect(
        a.copyWith(sortKey: () => 'hours'),
        isNot(a.copyWith(sortKey: () => 'hours', isAscending: false)),
      );
      expect(
        const SmartViewQuery(
          conditions: [
            SvCondition('hours', 'between', {'from': '1', 'to': '3'}),
          ],
        ),
        isNot(
          const SmartViewQuery(
            conditions: [
              SvCondition('hours', 'between', {'from': '1', 'to': '5'}),
            ],
          ),
        ),
      );
    });

    test('the same query reuses its result; two queries never share one', () {
      c.setConditions(const [SvCondition('title', 'contains', 'a')]);
      final first = c.shownRows;
      expect(identical(first, c.shownRows), isTrue);
      c.setConditions(const [SvCondition('title', 'contains', 'z')]);
      final second = c.shownRows;
      expect(identical(first, second), isFalse);
      expect(second.map((r) => r.values['title']), ['Zeta audit']);
      c.setConditions(const [SvCondition('title', 'contains', 'a')]);
      expect(c.shownRows.length, first.length);
    });

    test('new data with the same query is not served from the old result', () {
      c.setConditions(const [
        SvCondition('stage', 'in', ['Open']),
      ]);
      expect(titles().length, 3);
      final t = c.table.value!;
      // A live change: one Open row closes (a new row object, same id).
      final i = t.rows.indexWhere((r) => r.id == 1);
      t.rows[i] = t.rows[i].copyWith(
        values: {...t.rows[i].values, 'stage': 'Closed'},
      );
      expect(titles().length, 2);
      // A row appears.
      t.rows.add(_rows('tickets', offset: 100).first);
      expect(titles().length, 3);
    });
  });

  group('per view', () {
    test('filters on view A do not leak to view B and come back', () async {
      rig.socket.answers['submissions.list'] = listPager([
        for (final r in _rows('tickets'))
          ownRow(r.id, ts: r.ts, values: r.values),
      ]);
      rig.socket.answers['records.mine'] = {
        'submissions': <Object>[],
        'hasMore': false,
      };
      final a = sourceNamed('tickets');
      final other = realSources().firstWhere((s) => s.name != 'tickets');
      await c.show(a);
      await pumpMicro();
      c.setConditions(const [SvCondition('title', 'contains', 'alpha')]);
      expect(c.query.value.conditions.length, 1);
      await c.show(other);
      expect(c.query.value.isEmpty, isTrue);
      c.setConditions(const [SvCondition('#by', 'contains', 'ann')]);
      await c.show(a);
      expect(c.query.value.conditions, const [
        SvCondition('title', 'contains', 'alpha'),
      ]);
      await c.show(other);
      expect(c.query.value.conditions, const [
        SvCondition('#by', 'contains', 'ann'),
      ]);
    });
  });

  group('each operator type changes the result', () {
    void expectFilter(SvCondition cond, List<String> want) {
      c.setConditions([cond]);
      expect(titles(), want, reason: '${cond.col} ${cond.op}');
      expect(c.query.value.isFiltering, isTrue);
      c.setConditions(const []);
      expect(titles().length, 6);
    }

    test('text contains / is / is not / starts with', () {
      expectFilter(const SvCondition('title', 'contains', 'alpha'), [
        'Alpha invoice',
      ]);
      expectFilter(const SvCondition('title', 'equals', 'Badge lost'), [
        'Badge lost',
      ]);
      expectFilter(const SvCondition('title', 'starts', 'Zeta'), [
        'Zeta audit',
      ]);
      c.setConditions(const [SvCondition('title', 'not', 'Badge lost')]);
      expect(titles().length, 5);
    });

    test('number eq / gt / between', () {
      expectFilter(const SvCondition('hours', 'eq', '4'), ['Router down']);
      expectFilter(const SvCondition('hours', 'gt', '8'), ['Zeta audit']);
      expectFilter(
        const SvCondition('hours', 'between', {'from': '3', 'to': '4'}),
        ['Router down', 'Badge lost'],
      );
    });

    test('date on / after / before / between', () {
      expectFilter(const SvCondition('due', 'on', '2026-11-20'), [
        'Printer jammed',
      ]);
      expectFilter(const SvCondition('due', 'after', '2026-11-30'), [
        'Laptop request',
      ]);
      expectFilter(const SvCondition('due', 'before', '2026-10-15'), [
        'Router down',
      ]);
      expectFilter(
        const SvCondition('due', 'between', {
          'from': '2026-11-01',
          'to': '2026-11-25',
        }),
        ['Printer jammed', 'Badge lost'],
      );
    });

    test('status / select, several values (multi-chips)', () {
      expectFilter(const SvCondition('stage', 'in', ['Closed']), [
        'Alpha invoice',
        'Zeta audit',
      ]);
      expectFilter(
        const SvCondition('stage', 'in', ['Closed', 'In progress']),
        ['Router down', 'Alpha invoice', 'Zeta audit'],
      );
    });

    test('checkbox yes / no', () {
      expectFilter(const SvCondition('urgent', 'true'), [
        'Printer jammed',
        'Laptop request',
        'Zeta audit',
      ]);
      expectFilter(const SvCondition('urgent', 'false'), [
        'Router down',
        'Alpha invoice',
        'Badge lost',
      ]);
    });

    test('through the draft for every kind', () {
      final d = draft();
      addRow(d, 'stage', 'in', ['Open']);
      addRow(d, 'hours', 'gte', '3');
      addRow(d, 'urgent', 'true');
      addRow(d, 'due', 'after', '2026-11-01');
      addRow(d, 'title', 'contains', 'e');
      expect(d.count, 1);
      apply(d);
      expect(titles(), ['Laptop request']);
      expect(c.query.value.activeConditions.length, 5);
    });
  });

  group('the sheet, through widgets', () {
    testWidgets('typing a value commits on every change; Apply, then remove '
        'and Apply again', (t) async {
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(
        GetMaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: SmartViewContent(controller: c)),
        ),
      );
      await pumpFor(t, 300);
      await t.tap(find.byIcon(Icons.filter_list));
      await pumpFor(t, 800);
      await t.tap(find.text('Add filter'));
      await pumpFor(t, 400);
      await t.tap(
        find.descendant(
          of: find.byType(SvFilterSheetBody),
          matching: find.text('No.'),
        ),
      );
      await pumpFor(t, 300);
      await t.tap(find.text('Title').last);
      await pumpFor(t, 300);
      await t.enterText(find.widgetWithText(TextField, 'Value'), 'alpha');
      await pumpFor(t, 300);
      expect(find.text('1 of 6 records'), findsOneWidget);
      await t.tap(find.text('Apply'));
      await pumpFor(t, 800);
      expect(titles(), ['Alpha invoice']);
      expect(find.text('Title contains alpha'), findsOneWidget);
      expect(find.text('Router down'), findsNothing);

      await t.tap(find.byIcon(Icons.filter_list));
      await pumpFor(t, 800);
      expect(find.text('1 of 6 records'), findsOneWidget);
      await t.tap(find.byIcon(Icons.close).last);
      await pumpFor(t, 400);
      expect(find.text('6 of 6 records'), findsOneWidget);
      // Still filtered behind the sheet until Apply.
      expect(titles(), ['Alpha invoice']);
      await t.tap(find.text('Apply'));
      await pumpFor(t, 800);
      expect(titles().length, 6);
      expect(find.text('Title contains alpha'), findsNothing);
      expect(find.text('Router down'), findsOneWidget);
    });
  });
}
