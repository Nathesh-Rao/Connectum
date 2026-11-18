import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/smart_view/engine/sv_engine.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/sv_columns.dart';
import 'package:connectum/data/smart_view/sv_prefs.dart';
import 'package:connectum/data/smart_view/sv_query.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:connectum/features/smart_view/smart_view_view.dart';
import 'package:connectum/features/smart_view/widgets/sv_filter_draft.dart';
import 'package:connectum/features/smart_view/widgets/sv_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'sv_support.dart';

/// Every field the filter and sort sheets offer, with every operator, run on
/// the controller: each one must change the visible rows the way its own
/// meaning says, and removing it must restore them.

class _NoSubmissions extends GetxService implements SubmissionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int _ts(int day, int hour) =>
    DateTime(2026, 11, day, hour, 30).millisecondsSinceEpoch;

Map<String, dynamic> _raw(
  int id, {
  required String by,
  required String byName,
  required int ts,
  String status = '',
  required Map<String, dynamic> values,
  Map<String, dynamic> labels = const {},
}) => {
  'id': id,
  'by': by,
  'byName': byName,
  'ts': ts,
  'status': status,
  'tstruct': 'everyfield',
  'canEdit': true,
  'values': values,
  'labels': labels,
};

List<SvRow> _rows() => [
  for (final r in [
    _raw(
      11,
      by: 'ann',
      byName: 'Ann Rao',
      ts: _ts(2, 9),
      status: 'pending',
      values: {
        'ref': 'VIS-0001',
        'title': 'Printer jammed',
        'notes': 'second floor',
        'story': '<p>Hello <b>world</b></p>',
        'qty': 7,
        'amount': 1234.5,
        'day': '2026-11-12',
        'at': '09:45',
        'mail': 'a@b.co',
        'site': 'https://example.com/x',
        'phone': '+919886012345',
        'where': {'address': 'MG Road', 'lat': 12.9, 'lng': 77.5},
        'kind': 'Contract',
        'tags': ['red', 'blue'],
        'owner': 'bob',
        'stage': 'Open',
        'urgent': 'Yes',
        'code': '8901234567890',
        'copy': 'alpha',
        'fee': {'amount': 500, 'currency': 'INR', 'method': 'UPI'},
      },
      labels: {'owner': 'Bob Iyer'},
    ),
    _raw(
      12,
      by: 'bob',
      byName: 'Bob Iyer',
      ts: _ts(5, 14),
      status: 'approved',
      values: {
        'ref': 'VIS-0002',
        'title': 'Router down',
        'notes': 'basement',
        'qty': 3,
        'amount': 99,
        'day': '2026-10-02',
        'at': '18:05',
        'mail': 'zed@x.io',
        'site': 'https://example.org',
        'phone': '+911234567890',
        'kind': 'Invoice',
        'tags': ['green'],
        'owner': 'ann',
        'stage': 'In progress',
        'urgent': false,
        'code': '123',
        'copy': 'beta',
      },
      labels: {'owner': 'Ann Rao'},
    ),
    _raw(
      13,
      by: 'ann',
      byName: 'Ann Rao',
      ts: _ts(9, 8),
      status: 'rejected',
      values: {
        'ref': 'VIS-0003',
        'title': 'Alpha invoice',
        'qty': 12,
        'amount': 15000,
        'day': '2026-12-05',
        'kind': 'Contract',
        'tags': ['red'],
        'stage': 'Done',
        'urgent': 'No',
      },
    ),
    _raw(
      14,
      by: 'cy',
      byName: '',
      ts: _ts(9, 20),
      values: {
        'ref': 'VIS-0004',
        'title': 'Zeta audit',
        'qty': 1,
        'amount': 0.5,
        'day': '2026-11-12',
        'at': '07:00',
        'kind': 'Quote',
        'stage': 'Open',
        'urgent': true,
      },
    ),
    // Bare: only what a record always has.
    _raw(
      15,
      by: 'bob',
      byName: 'Bob Iyer',
      ts: _ts(20, 11),
      status: 'approved',
      values: {'ref': 'VIS-0005', 'stage': 'Open'},
    ),
  ])
    SvRow.tryParse(r, isReceived: false)!,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SvRig rig;
  late SmartViewController c;

  void init() {
    Get.reset();
    rig = SvRig();
    Get.put<SmartViewRepository>(rig.repo);
    Get.put<TicketRepository>(rig.tickets);
    c = SmartViewController(
      repo: rig.repo,
      tickets: rig.tickets,
      submissions: _NoSubmissions(),
      prefs: SmartViewPrefs(),
      newTicketDetail: (id) => throw UnimplementedError(),
    );
    c.clock = () => DateTime(2026, 11, 16, 12);
    final source = sourceNamed('everyfield');
    c.current.value = source;
    c.table.value = SvTable(source)
      ..rows.assignAll(_rows())
      ..phase.value = SvPhase.ready;
  }

  tearDown(() {
    rig.tickets.onClose();
    rig.repo.onClose();
    Get.reset();
  });

  List<int> shown() => [for (final r in c.shownRows) r.id];
  final all = [11, 12, 13, 14, 15];

  // What the person sees in a cell: the text; blank is empty.
  String seen(SvColumn col, SvRow r) {
    final cell = c.columns!.cellOf(col, r);
    return cell.isEmpty ? '' : cell.text;
  }

  Object? rawOf(SvColumn col, SvRow r) => c.columns!.cellOf(col, r).typed;

  double? num0(Object? v) => v is num
      ? v.toDouble()
      : (v is String ? double.tryParse(v.replaceAll(',', '')) : null);

  int? day(Object? v) {
    if (v is int) {
      final t = DateTime.fromMillisecondsSinceEpoch(v);
      return t.year * 10000 + t.month * 100 + t.day;
    }
    if (v is String && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(v)) {
      return int.parse(v.substring(0, 10).replaceAll('-', ''));
    }
    return null;
  }

  test('the sheets offer every column the engine can read', () {
    init();
    final input = c.engineInput!;
    final draft = SvFilterDraft(input, SmartViewQuery.none);
    final offered = {for (final f in draft.fields) f.key};
    expect(
      offered,
      containsAll([
        SmartViewColumns.noKey,
        SmartViewColumns.byKey,
        SmartViewColumns.submittedKey,
        SmartViewColumns.statusKey,
        'stage',
        'qty',
        'amount',
        'day',
        'urgent',
        'owner',
      ]),
    );
    for (final f in draft.fields) {
      expect(
        input.col(f.key),
        isNotNull,
        reason: '${f.label} unknown to engine',
      );
      expect(draft.opsOf(f), isNotEmpty, reason: f.label);
    }
  });

  test('every filter field and operator changes the rows as it says', () {
    init();
    final draft = SvFilterDraft(c.engineInput!, SmartViewQuery.none);
    final noops = <String>[];
    var combos = 0;

    for (final col in draft.fields) {
      final rows = c.table.value!.rows.toList();
      final texts = [for (final r in rows) seen(col, r)];
      final raws = [for (final r in rows) rawOf(col, r)];
      final filled = [
        for (var i = 0; i < rows.length; i++)
          if (texts[i].isNotEmpty) i,
      ];
      final firstText = texts[filled.first];

      for (final op in draft.opsOf(col)) {
        final kind = draft.kindOf(col, op);
        Object? value;
        late bool Function(int i) want;
        switch (op) {
          case '':
            continue;
          case 'empty':
            want = (i) => texts[i].isEmpty;
          case 'filled':
            want = (i) => texts[i].isNotEmpty;
          case 'true':
            want = (i) =>
                const {'yes', 'true', '1'}.contains(texts[i].toLowerCase());
          case 'false':
            want = (i) =>
                const {'no', 'false', '0'}.contains(texts[i].toLowerCase());
          case 'in':
            value = [firstText];
            want = (i) => texts[i].toLowerCase() == firstText.toLowerCase();
          case 'contains':
            value = firstText.substring(firstText.length - 3).toLowerCase();
            want = (i) => texts[i].toLowerCase().contains(value! as String);
          case 'starts':
            value = firstText;
            want = (i) => texts[i].toLowerCase().startsWith(
              (value! as String).toLowerCase(),
            );
          case 'equals':
            value = firstText;
            want = (i) => texts[i].toLowerCase() == firstText.toLowerCase();
          case 'not':
            value = firstText;
            want = (i) => texts[i].toLowerCase() != firstText.toLowerCase();
          case 'eq' || 'ne' || 'gt' || 'gte' || 'lt' || 'lte':
            final nums = [for (final r in raws) num0(r)];
            final sorted = nums.whereType<double>().toList()..sort();
            final pivot = sorted[sorted.length ~/ 2];
            value = pivot;
            want = (i) {
              final a = nums[i];
              if (a == null) return false;
              return switch (op) {
                'eq' => a == pivot,
                'ne' => a != pivot,
                'gt' => a > pivot,
                'gte' => a >= pivot,
                'lt' => a < pivot,
                _ => a <= pivot,
              };
            };
          case 'between' when kind == SvValueKind.numberRange:
            final nums = [for (final r in raws) num0(r)];
            final sorted = nums.whereType<double>().toList()..sort();
            final lo = sorted[1], hi = sorted[sorted.length - 2];
            value = {'from': lo, 'to': hi};
            want = (i) => nums[i] != null && nums[i]! >= lo && nums[i]! <= hi;
          case 'on' || 'after' || 'before':
            final days = [for (final r in raws) day(r)];
            final sorted = days.whereType<int>().toList()..sort();
            final pivot = sorted[sorted.length ~/ 2];
            value =
                '${pivot ~/ 10000}-'
                '${(pivot ~/ 100 % 100).toString().padLeft(2, '0')}-'
                '${(pivot % 100).toString().padLeft(2, '0')}';
            want = (i) {
              final d = days[i];
              if (d == null) return false;
              return switch (op) {
                'on' => d == pivot,
                'after' => d > pivot,
                _ => d < pivot,
              };
            };
          case 'between':
            final days = [for (final r in raws) day(r)];
            final sorted = days.whereType<int>().toList()..sort();
            String iso(int p) =>
                '${p ~/ 10000}-'
                '${(p ~/ 100 % 100).toString().padLeft(2, '0')}-'
                '${(p % 100).toString().padLeft(2, '0')}';
            final lo = sorted[1], hi = sorted[sorted.length - 2];
            value = {'from': iso(lo), 'to': iso(hi)};
            want = (i) => days[i] != null && days[i]! >= lo && days[i]! <= hi;
          default:
            fail('${col.label}: operator $op has no test');
        }

        final expected = [
          for (var i = 0; i < rows.length; i++)
            if (want(i)) rows[i].id,
        ];
        c.setConditions([SvCondition(col.key, op, value)]);
        final got = shown();
        combos++;
        expect(
          got,
          expected,
          reason: '${col.label} (${col.key}) $op ${value ?? ''}',
        );
        if (got.length == all.length) noops.add('${col.label} $op');
        c.setConditions(const []);
        expect(shown(), all, reason: 'removing ${col.label} $op restores');
      }
    }
    // Only "is filled" on a column every record has may leave all rows.
    for (final n in noops) {
      expect(
        n,
        anyOf(
          'No. filled',
          'By filled',
          'Submitted filled',
          'Status filled',
          'Ref filled',
          'Stage filled',
        ),
      );
    }
    expect(combos, greaterThan(100));
  });

  test('every sort field orders the rows and turns around', () {
    init();
    final draft = SvFilterDraft(c.engineInput!, SmartViewQuery.none);
    final cols = [
      for (final col in c.columns!.columns)
        if (col.type != SvColType.file) col,
    ];
    expect(cols.map((e) => e.key), containsAll(draft.fields.map((e) => e.key)));
    for (final col in cols) {
      final rows = c.table.value!.rows.toList();
      final distinct = {
        for (final r in rows)
          if (seen(col, r).isNotEmpty) seen(col, r),
      };
      String key(SvRow r) => seen(col, r).toLowerCase();
      final isNum = col.type == SvColType.number;
      final isDate =
          col.type == SvColType.date || col.type == SvColType.datetime;
      num? numKey(SvRow r) => isNum ? num0(rawOf(col, r)) : day(rawOf(col, r));
      List<int> oracle({required bool isAsc}) {
        final filled = [
          for (final r in rows)
            if (seen(col, r).isNotEmpty) r,
        ];
        final blank = [
          for (final r in rows)
            if (seen(col, r).isEmpty) r,
        ];
        int cmp(SvRow a, SvRow b) {
          final k = (isNum || isDate)
              ? (isDate && rawOf(col, a) is int
                    ? (rawOf(col, a)! as int).compareTo(rawOf(col, b)! as int)
                    : numKey(a)!.compareTo(numKey(b)!))
              : key(a).compareTo(key(b));
          final v = isAsc ? k : -k;
          return v != 0 ? v : rows.indexOf(a).compareTo(rows.indexOf(b));
        }

        filled.sort(cmp);
        return [
          for (final r in [...filled, ...blank]) r.id,
        ];
      }

      c.setSort(col.key, isAscending: true);
      final asc = shown();
      c.setSort(col.key, isAscending: false);
      final desc = shown();
      expect(asc, oracle(isAsc: true), reason: '${col.label} ascending');
      expect(desc, oracle(isAsc: false), reason: '${col.label} descending');
      if (distinct.length > 1) {
        expect(asc, isNot(desc), reason: '${col.label} asc == desc');
        expect(
          asc == all && desc == all,
          isFalse,
          reason: '${col.label} sort is a no-op',
        );
      }
      c.clearSort();
      expect(shown(), all, reason: 'removing the ${col.label} sort restores');
    }
  });

  test('a filter and a sort together, and Clear puts everything back', () {
    init();
    c.setConditions([
      const SvCondition(SmartViewColumns.statusKey, 'in', ['Approved']),
    ]);
    expect(shown(), [12, 15]);
    c.setSort(SmartViewColumns.noKey, isAscending: false);
    expect(shown(), [15, 12]);
    c.clearQuery();
    expect(shown(), all);
  });

  test('every Apply, remove and Clear logs one line: kinds, rows, cache', () {
    init();
    final lines = <String>[];
    final old = debugPrint;
    debugPrint = (m, {wrapWidth}) => lines.add(m ?? '');
    addTearDown(() => debugPrint = old);

    c.setConditions([
      const SvCondition('qty', 'gt', '3'),
      const SvCondition(SmartViewColumns.statusKey, 'in', ['Approved']),
    ]);
    c.removeCondition(c.query.value.conditions.first);
    c.clearFilters();
    c.setConditions([const SvCondition('title', 'contains', 'printer')]);
    c.clearQuery();

    final q = lines.where((l) => l.contains('smartview query')).toList();
    expect(q, hasLength(5));
    expect(
      q[0],
      '[records] smartview query view=everyfield filters=2 '
      'kinds=[number/gt, status/in] rows=5->0 cache=miss',
    );
    expect(
      q[1],
      '[records] smartview query view=everyfield filters=1 '
      'kinds=[status/in] rows=0->2 cache=miss',
    );
    expect(q[2], contains('filters=0 kinds=[] rows=2->5'));
    expect(q[3], contains('kinds=[text/contains] rows=5->1'));
    expect(q[4], contains('filters=0'));
    for (final l in q) {
      expect(l, isNot(contains('printer')));
      expect(l, isNot(contains('Approved')));
      expect(l, isNot(contains('qty')));
    }
  });

  group('the sheet, through widgets', () {
    Future<void> pumpFor(WidgetTester t, [int ms = 600]) async {
      for (var x = 0; x < ms; x += 50) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('Apply closes the sheet and the chip is there at once, also '
        'after the view was switched', (t) async {
      init();
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

      Future<void> applyNumberFilter(String value) async {
        await t.tap(find.byIcon(Icons.filter_list));
        await pumpFor(t, 800);
        await t.tap(find.text('Add filter'));
        await pumpFor(t, 400);
        await t.enterText(find.widgetWithText(TextField, 'Number'), value);
        await pumpFor(t, 300);
        await t.tap(find.text('Apply'));
        await pumpFor(t, 800);
        expect(find.byType(SvFilterSheetBody), findsNothing);
      }

      await applyNumberFilter('12');
      expect(shown(), [12]);
      expect(find.text('No. = 12'), findsOneWidget);

      // The view is switched to another structure (a new table, as `show`
      // does); the next sheet belongs to it, not to the first one.
      c.clearQuery();
      final other = sourceNamed('tickets');
      c.current.value = other;
      c.table.value = SvTable(other)
        ..rows.assignAll([
          for (final id in [31, 32, 33])
            SvRow.tryParse({
              'id': id,
              'by': 'ann',
              'byName': 'Ann Rao',
              'ts': _ts(3, 9),
              'tstruct': 'tickets',
              'values': {'title': 'T$id', 'stage': 'Open'},
            }, isReceived: false)!,
        ])
        ..phase.value = SvPhase.ready;
      await pumpFor(t, 300);
      await applyNumberFilter('32');
      expect(shown(), [32]);
      expect(find.text('No. = 32'), findsOneWidget);
    });
  });
}
