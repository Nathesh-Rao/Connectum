import 'package:connectum/core/debug/seed_smart_view.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/models/sv_source.dart';
import 'package:connectum/data/smart_view/sv_columns.dart';
import 'package:connectum/data/smart_view/sv_prefs.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:connectum/features/smart_view/widgets/smart_view_card.dart';
import 'package:connectum/features/smart_view/widgets/smart_view_mode_switch.dart';
import 'package:connectum/features/smart_view/widgets/smart_view_status_pill.dart';
import 'package:connectum/features/smart_view/widgets/smart_view_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sv_support.dart';

/// Bounded pumps: never pumpAndSettle.
Future<void> pumpFor(WidgetTester tester, [int ms = 500]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

SvSource _source({String key = 'title', bool withStatus = true}) =>
    SvSource.tryParse({
      'name': 'leave',
      'caption': 'Leave',
      'keyField': key,
      'status': withStatus
          ? {
              'field': 'stage',
              'statuses': ['Open', 'Done'],
              'final': ['Done'],
            }
          : null,
      'fields': [
        {'name': 'title', 'caption': 'Reason', 'type': 'text'},
        {'name': 'stage', 'caption': 'Stage', 'type': 'selection'},
        {'name': 'from', 'caption': 'From', 'type': 'date'},
        {'name': 'days', 'caption': 'Days', 'type': 'number'},
        {'name': 'at', 'caption': 'At', 'type': 'time'},
        {'name': 'ok', 'caption': 'Cover', 'type': 'toggle'},
        {'name': 'sig', 'caption': 'Signature', 'type': 'signature'},
        {'name': 'a', 'caption': 'A', 'type': 'text'},
        {'name': 'b', 'caption': 'B', 'type': 'text'},
      ],
    })!;

SvRow _row(int id, Map<String, dynamic> values) => SvRow(
  id: id,
  tstruct: 'leave',
  by: 'ana',
  byName: 'Ana Rao',
  ts: 1794833216651,
  values: {...values, 'secret': 'HIDDEN-VALUE'},
);

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    backgroundColor: Colors.white,
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmartViewColumns', () {
    final cols = SmartViewColumns.of(_source());

    test('meta columns come first, then the key, status and own fields', () {
      expect(
        [for (final c in cols.columns) c.label],
        [
          'No.',
          'Reason',
          'By',
          'Submitted',
          'Status',
          'Stage',
          'From',
          'Days',
          'At',
          'Cover',
          'Signature',
          'A',
          'B',
        ],
      );
      expect(cols.metaColumns.map((c) => c.label), [
        'No.',
        'By',
        'Submitted',
        'Status',
      ]);
      expect(cols.ownColumns.every((c) => !c.isMeta), isTrue);
    });

    test('types map from the field types the app knows', () {
      SvColType of(String k) => cols.columns.firstWhere((c) => c.key == k).type;
      expect(of('title'), SvColType.text);
      expect(of('stage'), SvColType.status);
      expect(of('from'), SvColType.date);
      expect(of('days'), SvColType.number);
      expect(of('at'), SvColType.time);
      expect(of('ok'), SvColType.checkbox);
      expect(of('sig'), SvColType.unknown);
    });

    test('a hidden field is never a column or a cell', () {
      final row = _row(1, {'title': 'Trip'});
      expect(cols.columns.any((c) => c.key == 'secret'), isFalse);
      for (final c in cols.cellsOf(row)) {
        expect(c.text, isNot(contains('HIDDEN')));
        expect(c.typed, isNot('HIDDEN-VALUE'));
      }
      final card = cols.cardOf(row);
      expect(card.fields.any((f) => f.cell.text.contains('HIDDEN')), isFalse);
    });

    test('an empty value is the dash, an unknown type is raw text', () {
      final row = _row(2, {
        'title': 'Trip',
        'sig': {'by': 'ana', 'n': 2},
      });
      final byKey = {for (final c in cols.columns) c.key: cols.cellOf(c, row)};
      expect(byKey['from']!.text, SmartViewColumns.empty);
      expect(byKey['from']!.isEmpty, isTrue);
      expect(byKey['sig']!.text, 'by: ana · n: 2');
      expect(byKey['#no']!.text, '2');
      expect(byKey['#by']!.text, 'Ana Rao');
      expect(byKey['#status']!.text, 'Recorded');
    });

    test('the card keeps meta apart and leaves the title and status out', () {
      final card = cols.cardOf(_row(3, {'title': 'Trip', 'stage': 'Open'}));
      expect(card.title, 'Trip');
      expect(card.ticketStatus, 'Open');
      expect(card.number, '3');
      final keys = card.fields.map((f) => f.column.key);
      expect(keys, isNot(contains('title')));
      expect(keys, isNot(contains('stage')));
      expect(keys, isNot(contains('#no')));
    });
  });

  group('SmartViewCard', () {
    final cols = SmartViewColumns.of(_source());
    final full = cols.cardOf(
      _row(7, {
        'title': 'Trip',
        'stage': 'In progress',
        'from': '2026-12-01',
        'days': 3,
        'at': '09:30',
        'ok': true,
        'sig': 'x',
        'a': 'aa',
        'b': 'bb',
      }),
    );
    final few = SmartViewColumns.of(
      SvSource.tryParse({
        'name': 'x',
        'caption': 'X',
        'keyField': 'title',
        'fields': [
          {'name': 'title', 'caption': 'Title'},
          {'name': 'a', 'caption': 'A'},
          {'name': 'b', 'caption': 'B'},
        ],
      })!,
    ).cardOf(_row(8, {'title': 'Small', 'a': '1', 'b': '2'}));

    testWidgets('has no buttons, progress or menu, and shows the pills', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(SmartViewCard(data: few, isExpanded: false, onToggle: () {})),
      );
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(PopupMenuButton), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SmartViewStatusPill), findsOneWidget);
      expect(find.text('Show all (2)'), findsNothing);
      expect(find.textContaining('Show'), findsNothing);
    });

    testWidgets('six fields or fewer have no expand control', (tester) async {
      final six = SmartViewColumns.of(
        _source(),
      ).cardOf(_row(9, {'title': 'T', 'stage': 'Open'}));
      // the source has 7 own fields besides the key and status: use 6 of them
      final trimmed = SvCardData(
        title: six.title,
        status: six.status,
        ticketStatus: six.ticketStatus,
        number: six.number,
        by: six.by,
        submitted: six.submitted,
        fields: six.fields.take(6).toList(),
      );
      await tester.pumpWidget(
        _host(SmartViewCard(data: trimmed, isExpanded: false, onToggle: () {})),
      );
      expect(find.textContaining('Show'), findsNothing);
    });

    testWidgets('more than six: Show all expands and Show less collapses, '
        'and the state outlives a rebuild', (tester) async {
      final expanded = <int>{};
      late StateSetter set;
      Widget build() => _host(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return SmartViewCard(
              data: full,
              isExpanded: expanded.contains(7),
              onToggle: () => setState(() {
                if (!expanded.remove(7)) expanded.add(7);
              }),
            );
          },
        ),
      );
      await tester.pumpWidget(build());
      expect(full.fields.length, greaterThan(6));
      expect(find.text('Show all (${full.fields.length})'), findsOneWidget);
      expect(find.text('B'), findsNothing);
      await tester.tap(find.text('Show all (${full.fields.length})'));
      await pumpFor(tester, 400);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);
      // a rebuild of the whole list keeps it open
      await tester.pumpWidget(build());
      set(() {});
      await pumpFor(tester, 100);
      expect(find.text('B'), findsOneWidget);
      await tester.tap(find.text('Show less'));
      await pumpFor(tester, 400);
      expect(find.text('B'), findsNothing);
    });

    test('the controller keeps the expanded ids for the session', () {
      final rig = SvRig();
      final c = SmartViewController(
        repo: rig.repo,
        tickets: rig.tickets,
        submissions: _NoSubmissions(),
        newTicketDetail: (_) => throw UnimplementedError(),
      );
      c.toggleExpanded(5);
      expect(c.expanded.contains(5), isTrue);
      c.toggleExpanded(5);
      expect(c.expanded.contains(5), isFalse);
      rig.tickets.onClose();
      rig.repo.onClose();
    });

    testWidgets('golden: short and expanded', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 900 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _host(SmartViewCard(data: few, isExpanded: false, onToggle: () {})),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_card_new_short.png'),
      );
      await tester.pumpWidget(
        _host(SmartViewCard(data: full, isExpanded: true, onToggle: () {})),
      );
      await pumpFor(tester, 300);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_card_new_expanded.png'),
      );
    });
  });

  group('SmartViewModeSwitch', () {
    testWidgets('both states, and a tap asks for the other', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 120 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      var mode = SvViewMode.cards;
      late StateSetter set;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topLeft,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    set = setState;
                    return SmartViewModeSwitch(
                      mode: mode,
                      onChanged: (m) => setState(() => mode = m),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(SmartViewModeSwitch)),
        const Size(96, 34),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_switch_cards.png'),
      );
      await tester.tap(find.bySemanticsLabel('Table'));
      await pumpFor(tester, 300);
      expect(mode, SvViewMode.table);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_switch_table.png'),
      );
      set(() => mode = SvViewMode.cards);
      await pumpFor(tester, 300);
    });
  });

  group('SmartViewPrefs', () {
    test('default is cards; the choice is written and restored', () async {
      final written = <String>[];
      final prefs = SmartViewPrefs(write: (v) async => written.add(v));
      expect(prefs.mode, SvViewMode.cards);
      await prefs.setMode(SvViewMode.table);
      expect(written, ['table']);
      final restored = SmartViewPrefs(mode: SvViewMode.table);
      final rig = SvRig();
      final c = SmartViewController(
        repo: rig.repo,
        tickets: rig.tickets,
        submissions: _NoSubmissions(),
        newTicketDetail: (_) => throw UnimplementedError(),
        prefs: restored,
      );
      expect(c.mode.value, SvViewMode.table);
      rig.tickets.onClose();
      rig.repo.onClose();
    });
  });

  group('SmartViewTable', () {
    final source = SeedSmartView.leaveSource();
    final rows = SeedSmartView.leaveRows();

    test('a column is as wide as its widest content, capped, then wraps', () {
      final columns = SmartViewColumns.of(source);
      final m = SmartViewTableMetrics.measure(
        columns: columns,
        rows: rows,
        maxWidth: 234,
      );
      final notes = columns.columns.indexWhere((c) => c.key == 'notes');
      final no = columns.columns.indexWhere((c) => c.key == '#no');
      expect(m.widths[notes], 234, reason: 'long text hits the cap');
      expect(m.widths[no], lessThan(120));
      expect(
        m.rowHeights[0],
        greaterThan(SmartViewTableMetrics.minRowHeight),
        reason: 'the long note wraps and the row grows',
      );
      final wider = SmartViewTableMetrics.measure(
        columns: columns,
        rows: rows,
        maxWidth: 6000,
      );
      expect(wider.widths[notes], greaterThan(234));
      expect(wider.rowHeights[0], SmartViewTableMetrics.minRowHeight);
    });

    Future<void> pumpTable(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: SmartViewTable(
              source: source,
              rows: rows,
              versions: const {},
              onRefresh: () async {},
              footer: const SizedBox(height: 24),
            ),
          ),
        ),
      );
      await pumpFor(tester, 200);
    }

    testWidgets('the long value is in the tree in full, pills are shown', (
      tester,
    ) async {
      await pumpTable(tester);
      final long = (SeedSmartView.leaveValues(0)['notes'] as String);
      expect(find.text(long), findsWidgets);
      expect(find.byType(SmartViewStatusPill), findsWidgets);
      expect(find.text('HIDDEN-DEMO-NOTE'), findsNothing);
    });

    testWidgets('the header stays while the rows scroll', (tester) async {
      await pumpTable(tester);
      final before = tester.getTopLeft(find.text('No.')).dy;
      final row = tester.getTopLeft(find.text('1000')).dy;
      await tester.dragFrom(const Offset(40, 500), const Offset(0, -400));
      await pumpFor(tester, 300);
      expect(tester.getTopLeft(find.text('No.')).dy, before);
      expect(row, greaterThan(before), reason: 'the first row was below it');
      expect(find.text('1000'), findsNothing, reason: 'the rows moved up');
    });

    testWidgets('golden: loaded', (tester) async {
      await pumpTable(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_table.png'),
      );
    });
  });
}

class _NoSubmissions extends Fake implements SubmissionRepository {}
