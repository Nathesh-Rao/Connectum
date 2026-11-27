import 'package:connectum/features/inbox/inbox_view.dart';
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

  final pill = find.byKey(const ValueKey('inbox-records-count'));

  Future<void> pump(
    WidgetTester t, {
    double width = 390,
    double scale = 1,
    int records = 7,
    int? total,
    bool isCapped = false,
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
        : queryReply(
            [for (var i = records; i > 0; i--) record(i)],
            total: total,
            capped: isCapped,
          );
    rig.routes['req.list'] = (_) => {
      'requests': [_req(1)],
      'total': 1,
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const InboxView(),
      ),
    );
    await settle(t);
  }

  final approvalsPill = find.byKey(const ValueKey('inbox-approvals-count'));

  for (final cfg in [(390.0, 1.0), (320.0, 1.5)]) {
    testWidgets('records pill is compact at ${cfg.$1}px x${cfg.$2}', (t) async {
      await pump(t, width: cfg.$1, scale: cfg.$2);
      expect(t.takeException(), isNull);
      expect(pill, findsOneWidget);
      final text = find.descendant(of: pill, matching: find.byType(Text));
      final r = t.getRect(pill);
      expect(r.height, lessThan(30 * cfg.$2));
      expect((r.center.dy - t.getRect(text).center.dy).abs(), lessThan(1.5));
      expect(r.width, greaterThanOrEqualTo(r.height - 0.5));
      expect(find.text('Records'), findsOneWidget);
    });

    testWidgets('approvals pill is compact at ${cfg.$1}px x${cfg.$2}', (
      t,
    ) async {
      await pump(t, width: cfg.$1, scale: cfg.$2);
      expect(approvalsPill, findsOneWidget);
      final r = t.getRect(approvalsPill);
      final text = find.descendant(of: approvalsPill, matching: find.text('1'));
      expect(r.height, lessThan(30 * cfg.$2));
      expect((r.center.dy - t.getRect(text).center.dy).abs(), lessThan(1.5));
      expect(r.width, greaterThanOrEqualTo(r.height - 0.5));
    });
  }

  testWidgets('pill widens with digits and keeps its height', (t) async {
    await pump(t, records: 1, total: 1);
    final one = t.getRect(pill);
    final glyph = t.getSize(
      find.descendant(of: pill, matching: find.text('1')),
    );
    expect(
      one.width,
      closeTo(glyph.width + 12 < one.height ? one.height : glyph.width + 12, 1),
    );
    await pump(t, records: 12, total: 12);
    final two = t.getRect(pill);
    await pump(t, records: 99, total: 99);
    final ninety = t.getRect(pill);
    await pump(t, records: 20, total: 1001, isCapped: true);
    final big = t.getRect(pill);
    expect(two.width, greaterThan(one.width - 0.5));
    expect(big.width, greaterThan(two.width));
    for (final r in [two, ninety, big]) {
      expect(r.height, closeTo(one.height, 0.5));
    }
  });
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
