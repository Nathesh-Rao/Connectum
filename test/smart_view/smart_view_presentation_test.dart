import 'dart:ui';

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
import 'package:connectum/core/widgets/card_top_right_decoration.dart';
import 'package:flutter/rendering.dart';
import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_sv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    testWidgets('header: position, title, status pill; painter present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SmartViewCard(
            data: full,
            position: 7,
            isExpanded: false,
            onToggle: () {},
          ),
        ),
      );
      final card = find.byType(SmartViewCard);
      final pos = find.byKey(const ValueKey('sv-card-position'));
      expect(
        find.descendant(of: pos, matching: find.text('7')),
        findsOneWidget,
      );
      expect(tester.getSize(pos), const Size(30, 30));
      expect(find.text(full.title), findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byType(SmartViewStatusPill)),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byType(CardTopRightDecoration),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byType(CircleAvatar)),
        findsNothing,
      );
    });

    testWidgets('phone scale: 4 rows are 220 to 270 dp, header is 56 dp', (
      tester,
    ) async {
      final four = SmartViewColumns.of(
        SvSource.tryParse({
          'name': 'x',
          'caption': 'X',
          'keyField': 'title',
          'fields': [
            {'name': 'title', 'caption': 'Title'},
            {'name': 'a', 'caption': 'A'},
          ],
        })!,
      ).cardOf(_row(9, {'title': 'Four', 'a': '1'}));
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        _host(SmartViewCard(data: four, isExpanded: false, onToggle: () {})),
      );
      final h = tester.getSize(find.byType(SmartViewCard)).height;
      expect(h, inInclusiveRange(220, 270));
      // the decoration fills the card and takes no layout space of its own
      final deco = tester.getRect(find.byType(CardTopRightDecoration));
      final cardRect = tester.getRect(find.byType(SmartViewCard));
      expect(deco.height, closeTo(h, 2.1));
      expect(deco.width, closeTo(cardRect.width, 2.1));
      expect(
        tester.getRect(find.byKey(const ValueKey('sv-card-position'))).top,
        greaterThan(cardRect.top),
      );
    });

    test('decoration path: closed, inside the top-right region', () {
      final painter = CardTopRightDecorationPainter(size: const Size(360, 240));
      final path = painter.pathFor(const Size(360, 240));
      final b = path.getBounds();
      expect(b.left, greaterThanOrEqualTo(0.50 * 360));
      expect(b.bottom, lessThanOrEqualTo(0.36 * 240));
      expect(b.right, closeTo(360, 0.01));
      expect(b.top, 0);
      expect(path.computeMetrics().length, 1);
      expect(identical(painter.pathFor(const Size(360, 240)), path), isTrue);
    });

    test('decoration depth is clamped to 64 dp on tall cards', () {
      final b = CardTopRightDecorationPainter(
        size: const Size(360, 600),
      ).pathFor(const Size(360, 600)).getBounds();
      expect(b.bottom, lessThanOrEqualTo(AppSv.svDecoMaxDepth));
    });

    test('decoration shouldRepaint: size and colours only', () {
      final a = CardTopRightDecorationPainter(size: const Size(360, 240));
      expect(
        a.shouldRepaint(
          CardTopRightDecorationPainter(size: const Size(360, 240)),
        ),
        isFalse,
      );
      expect(
        a.shouldRepaint(
          CardTopRightDecorationPainter(size: const Size(320, 240)),
        ),
        isTrue,
      );
      expect(
        a.shouldRepaint(
          CardTopRightDecorationPainter(
            size: const Size(360, 240),
            softBlue: const Color(0xFF000000),
          ),
        ),
        isTrue,
      );
    });

    testWidgets('nothing is painted below 0.36 h (bottom-left is white)', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: _host(
            SmartViewCard(data: few, isExpanded: false, onToggle: () {}),
          ),
        ),
      );
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData())!;
        final card = tester.getRect(find.byType(SmartViewCard));
        for (final pt in [
          Offset(card.left + 4, card.bottom - 20),
          Offset(card.right - 6, card.top + card.height * 0.40),
          Offset(card.right - 6, card.bottom - 20),
        ]) {
          final o = (pt.dy.round() * image.width + pt.dx.round()) * 4;
          expect(
            [bytes.getUint8(o), bytes.getUint8(o + 1), bytes.getUint8(o + 2)],
            [255, 255, 255],
          );
        }
      });
    });

    testWidgets('a row region under the header is plain white', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: _host(
            SmartViewCard(data: few, isExpanded: false, onToggle: () {}),
          ),
        ),
      );
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = (await image.toByteData())!;
        final card = tester.getRect(find.byType(SmartViewCard));
        // the strip between the header band and the first value, left of
        // the icon column
        final x = (card.left + 4).round();
        final y = (card.top + AppSv.headerHeight + 6).round();
        final o = (y * image.width + x) * 4;
        expect(bytes.getUint8(o), 255);
        expect(bytes.getUint8(o + 1), 255);
        expect(bytes.getUint8(o + 2), 255);
      });
    });

    testWidgets('three-digit position shrinks to 11 sp', (tester) async {
      await tester.pumpWidget(
        _host(
          SmartViewCard(
            data: few,
            position: 128,
            isExpanded: false,
            onToggle: () {},
          ),
        ),
      );
      expect(tester.widget<Text>(find.text('128')).style!.fontSize, 11);
    });

    testWidgets('rows: icon + key left, value right, 50/50, same value x', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: [
              SmartViewCard(data: few, isExpanded: false, onToggle: () {}),
              SmartViewCard(data: full, isExpanded: false, onToggle: () {}),
            ],
          ),
        ),
      );
      final cards = find.byType(SmartViewCard);
      final xs = <double>{};
      for (final key in ['No.', 'By', 'Submitted']) {
        final keys = find.text(key);
        expect(keys, findsNWidgets(2));
        for (var i = 0; i < 2; i++) {
          final row = find.ancestor(of: keys.at(i), matching: find.byType(Row));
          final halves = find.descendant(
            of: row.last,
            matching: find.byType(Expanded),
          );
          final left = tester.getRect(halves.at(0));
          final right = tester.getRect(halves.last);
          expect(left.width, closeTo(right.width, 0.01));
          expect(
            find.descendant(of: row.last, matching: find.byType(Icon)),
            findsOneWidget,
          );
          expect(tester.getTopLeft(keys.at(i)).dx, lessThan(right.left));
          xs.add(right.left);
        }
      }
      expect(xs.length, 1, reason: 'all values start at the same x');
      expect(
        tester.getRect(cards.at(0)).width,
        tester.getRect(cards.at(1)).width,
      );
    });

    testWidgets('long key and value wrap in full, no ellipsis', (tester) async {
      const longKey = 'A very long field caption that has to wrap inside';
      const longValue =
          'A very long value that keeps going and going until it wraps '
          'over several lines inside its own half of the row';
      final c = SmartViewColumns.of(
        SvSource.tryParse({
          'name': 'x',
          'caption': 'X',
          'keyField': 'title',
          'fields': [
            {'name': 'title', 'caption': 'Title'},
            {'name': 'a', 'caption': longKey},
          ],
        })!,
      ).cardOf(_row(30, {'title': 'T', 'a': longValue}));
      await tester.pumpWidget(
        _host(SmartViewCard(data: c, isExpanded: false, onToggle: () {})),
      );
      for (final t in [longKey, longValue]) {
        final w = tester.widget<Text>(find.text(t));
        expect(w.overflow, isNot(TextOverflow.ellipsis));
        expect(w.maxLines, isNull);
      }
      expect(
        tester.getSize(find.text(longValue)).height,
        greaterThan(tester.getSize(find.text('Ana Rao')).height * 1.5),
      );
    });

    testWidgets('text scale 1.3 and 320 dp wide: no overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 1800),
            textScaler: TextScaler.linear(1.3),
          ),
          child: _host(
            SmartViewCard(data: full, isExpanded: true, onToggle: () {}),
          ),
        ),
      );
      await pumpFor(tester, 300);
      expect(tester.takeException(), isNull);
    });

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
      // No., By, Submitted and the status field come first: with 2 own
      // fields that is six pairs, so nothing is folded away
      final trimmed = SvCardData(
        title: six.title,
        status: six.status,
        ticketStatus: six.ticketStatus,
        number: six.number,
        by: six.by,
        submitted: six.submitted,
        fields: six.fields.take(2).toList(),
      );
      await tester.pumpWidget(
        _host(SmartViewCard(data: trimmed, isExpanded: false, onToggle: () {})),
      );
      expect(find.textContaining('Show'), findsNothing);
    });

    testWidgets('more than six: Show all expands and Show less collapses, '
        'and the state outlives a rebuild', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 2400 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
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
      // No., By, Submitted, Stage + the own fields
      final pairs = 4 + full.fields.length;
      expect(pairs, greaterThan(6));
      expect(find.text('Show all ($pairs)'), findsOneWidget);
      expect(find.text('B'), findsNothing);
      await tester.tap(find.text('Show all ($pairs)'));
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

  group('card at 320', () {
    testWidgets('golden: 320 dp wide', (tester) async {
      tester.view.physicalSize = const Size(320 * 2, 700 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      final data = SmartViewColumns.of(
        _source(),
      ).cardOf(_row(5, {'title': 'Trip', 'stage': 'Open', 'days': 3}));
      await tester.pumpWidget(
        _host(SmartViewCard(data: data, isExpanded: false, onToggle: () {})),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_card_320.png'),
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

    test('nothing wraps: a long note is cut at 10 words, rows stay fixed', () {
      final columns = SmartViewColumns.of(source);
      final m = SmartViewTableMetrics.measure(
        columns: columns,
        rows: rows,
        maxWidth: 6000,
      );
      final notes = columns.columns.indexWhere((c) => c.key == 'notes');
      final no = columns.columns.indexWhere((c) => c.key == '#no');
      final cut = m.cut[0][notes]!;
      expect(cut.endsWith('…'), isTrue);
      expect(
        cut.substring(0, cut.length - 1).trim().split(RegExp(r'\s+')).length,
        AppSv.tableMaxWords,
      );
      expect(m.cut[1][notes], isNull, reason: 'an empty note has no link');
      expect(m.cut[2][notes], isNull, reason: '"Short note" has no link');
      expect(m.widths[no], lessThan(120));
      expect(m.rowHeights.toSet(), {SmartViewTableMetrics.minRowHeight});
      final narrow = SmartViewTableMetrics.measure(
        columns: columns,
        rows: rows,
        maxWidth: 234,
      );
      expect(narrow.widths[notes], lessThanOrEqualTo(234));
      expect(narrow.widths[notes], lessThan(m.widths[notes]));
      expect(narrow.rowHeights.toSet(), {SmartViewTableMetrics.minRowHeight});
    });

    test('the column is as wide as the cut text plus its link', () {
      final columns = SmartViewColumns.of(source);
      final notes = columns.columns.indexWhere((c) => c.key == 'notes');
      final one = SmartViewTableMetrics.measure(
        columns: columns,
        rows: [rows[0]],
        maxWidth: 6000,
      );
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: one.cut[0][notes],
          style: SmartViewTableMetrics.cellStyle,
        ),
      )..layout();
      final more = TextPainter(
        textDirection: TextDirection.ltr,
        text: const TextSpan(text: 'View more', style: AppSv.tableMore),
      )..layout();
      expect(
        one.widths[notes],
        closeTo(
          painter.width +
              AppSv.tableMoreGap +
              more.width +
              2 * SmartViewTableMetrics.padX,
          1,
        ),
      );
    });

    test('shorten: words, then width; a long token is cut too', () {
      bool fits20(String t) => t.length <= 20;
      final words25 = List.generate(25, (i) => 'w$i').join(' ');
      expect(SmartViewTableMetrics.shorten('short text', fits20), isNull);
      final byWords = SmartViewTableMetrics.shorten(words25, (_) => true)!;
      expect(byWords, 'w0 w1 w2 w3 w4 w5 w6 w7 w8 w9…');
      final token = 'x' * 80;
      final byWidth = SmartViewTableMetrics.shorten(token, fits20)!;
      expect(byWidth.length, 20);
      expect(byWidth.endsWith('…'), isTrue);
      expect(
        SmartViewTableMetrics.shorten('one two three', fits20),
        isNull,
        reason: 'three words that fit are shown whole',
      );
    });

    /// The "View more" on the same line as the first long note.
    Finder notesMore() => find.descendant(
      of: find
          .ancestor(
            of: find.textContaining('Trav').first,
            matching: find.byType(Row),
          )
          .first,
      matching: find.text('View more'),
    );

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

    testWidgets('a cut cell is one line with View more; short ones have none', (
      tester,
    ) async {
      await pumpTable(tester);
      final long = (SeedSmartView.leaveValues(0)['notes'] as String);
      expect(find.text(long), findsNothing, reason: 'the table shows a cut');
      expect(find.text('View more'), findsWidgets);
      expect(find.byType(SmartViewStatusPill), findsWidgets);
      expect(find.text('HIDDEN-DEMO-NOTE'), findsNothing);
      final cut = find.textContaining('Trav').first;
      final text = tester.widget<Text>(cut);
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      final cell = find
          .ancestor(of: cut, matching: find.byType(Container))
          .first;
      expect(
        tester.getSize(cell).height,
        closeTo(SmartViewTableMetrics.minRowHeight, 1),
        reason: 'the row height less its hairline',
      );
      final line = tester.getRect(cut);
      final more = tester.getRect(notesMore());
      expect(more.left, greaterThan(line.right - 1));
      expect((more.center.dy - line.center.dy).abs(), lessThan(3));
    });

    testWidgets('View more opens Details with the full text and Copy', (
      tester,
    ) async {
      await pumpTable(tester);
      final long = (SeedSmartView.leaveValues(0)['notes'] as String);
      final clip = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clip.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.ensureVisible(notesMore());
      await pumpFor(tester, 200);
      await tester.tap(notesMore());
      await pumpFor(tester, 700);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Notes'), findsWidgets);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        long,
      );
      await tester.tap(find.text('Copy'));
      await pumpFor(tester, 300);
      expect(clip, [long]);
    });

    testWidgets('a long press on any cell opens Details too', (tester) async {
      await pumpTable(tester);
      await tester.ensureVisible(find.text('Rhea Kapoor').first);
      await pumpFor(tester, 200);
      await tester.longPress(find.text('Rhea Kapoor').first);
      await pumpFor(tester, 700);
      expect(find.text('Details'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        'Rhea Kapoor',
      );
    });

    testWidgets('a long single token over the width cap is cut', (
      tester,
    ) async {
      final token = 'https://example.com/${'a' * 120}';
      final src = SeedSmartView.leaveSource();
      final row = rows.first.copyWith(
        values: {...rows.first.values, 'notes': token},
      );
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartViewTable(
              source: src,
              rows: [row],
              versions: const {},
              onRefresh: () async {},
              footer: const SizedBox(height: 24),
            ),
          ),
        ),
      );
      await pumpFor(tester, 200);
      expect(find.text(token), findsNothing);
      final more = find.descendant(
        of: find
            .ancestor(
              of: find.textContaining('http'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.text('View more'),
      );
      await tester.ensureVisible(more);
      expect(find.textContaining('http'), findsOneWidget);
      expect(more, findsOneWidget);
      final m = SmartViewTableMetrics.measure(
        columns: SmartViewColumns.of(src),
        rows: [row],
        maxWidth: 390 * AppSv.tableMaxWidthShare,
      );
      expect(m.widths.every((w) => w <= 390 * 0.6 || w.isFinite), isTrue);
      final i = SmartViewColumns.of(
        src,
      ).columns.indexWhere((c) => c.key == 'notes');
      expect(m.widths[i], lessThanOrEqualTo(390 * 0.6));
    });

    testWidgets('golden: a cut cell with View more', (tester) async {
      await pumpTable(tester);
      await tester.ensureVisible(notesMore());
      await pumpFor(tester, 300);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_table.png'),
      );
    });

    testWidgets('golden: the Details sheet', (tester) async {
      await pumpTable(tester);
      await tester.ensureVisible(notesMore());
      await pumpFor(tester, 300);
      await tester.tap(notesMore());
      await pumpFor(tester, 700);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_cell_details_sheet.png'),
      );
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

    testWidgets('flat colours: no gradient, solid header, alternate rows', (
      tester,
    ) async {
      await pumpTable(tester);
      final table = find.byType(SmartViewTable);
      for (final b in tester.widgetList<DecoratedBox>(
        find.descendant(of: table, matching: find.byType(DecoratedBox)),
      )) {
        final d = b.decoration;
        if (d is BoxDecoration) expect(d.gradient, isNull);
      }
      for (final c in tester.widgetList<Container>(
        find.descendant(of: table, matching: find.byType(Container)),
      )) {
        final d = c.decoration;
        if (d is BoxDecoration) expect(d.gradient, isNull);
      }
      final head = tester
          .widgetList<Container>(
            find.descendant(of: table, matching: find.byType(Container)),
          )
          .firstWhere((c) => c.color == AppColors.primary);
      expect(head.color, AppSv.tableHeaderFill);
      expect(AppSv.tableHeaderFill, AppColors.primary);
      expect(AppSv.tableHead.color, AppColors.white);
      expect(AppSv.tableHead.fontSize, 13);
      expect(AppSv.tableHead.fontWeight, FontWeight.w700);
      final fills = tester
          .widgetList<Container>(
            find.descendant(of: table, matching: find.byType(Container)),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .where((c) => c == AppColors.white || c == AppSv.tableRowAlt)
          .toList();
      expect(fills.take(2), [AppColors.white, AppSv.tableRowAlt]);
      expect(AppSv.tableRowAlt.a, closeTo(0.045, 0.01));
      expect(
        AppSv.tableRowAlt.toARGB32() & 0xFFFFFF,
        AppColors.primary.toARGB32() & 0xFFFFFF,
      );
    });

    testWidgets('the header sits 20 dp below the top of the table', (
      tester,
    ) async {
      await pumpTable(tester);
      final top = tester.getRect(find.byType(SmartViewTable)).top;
      final head = tester
          .getRect(
            find
                .ancestor(
                  of: find.text('No.'),
                  matching: find.byType(Container),
                )
                .first,
          )
          .top;
      expect(AppSv.tableTopGap, 20);
      expect(head - top, 20);
    });
  });
}

class _NoSubmissions extends Fake implements SubmissionRepository {}
