import 'package:connectum/data/models/approval.dart';
import 'package:connectum/features/inbox/inbox_view.dart';
import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:connectum/features/inbox/widgets/approval_card.dart';
import 'package:connectum/features/inbox/widgets/inbox_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'inbox_screen_support.dart';

Map<String, dynamic> raw(
  int id, {
  String status = 'pending',
  bool canRespond = true,
}) => {
  'id': id,
  'type': 'submission',
  'status': status,
  'from': 'rhea',
  'fromName': 'Rhea Rao With A Rather Long Name',
  'approvers': ['ana'],
  'direction': canRespond ? 'incoming' : 'outgoing',
  'canRespond': canRespond,
  'createdTs': DateTime(2026, 11, 20, 9, id).millisecondsSinceEpoch,
  'data': {
    'caption': 'An expense claim with a rather long form caption',
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

  for (final c in [(width: 320.0, scale: 1.5), (width: 390.0, scale: 1.0)]) {
    testWidgets('the mixed list at ${c.width} px, text x${c.scale}', (
      tester,
    ) async {
      final rig = InboxRig();
      addTearDown(rig.dispose);
      rig.routes['records.query'] = (_) => queryReply([record(2), record(1)]);
      rig.routes['req.list'] = (_) => {
        'requests': [
          raw(1),
          raw(2, status: 'accepted', canRespond: false),
          raw(3, status: 'rejected', canRespond: false),
        ],
        'total': 3,
        'hasMore': false,
      };
      Get.put(rig.controller);
      addTearDown(Get.reset);
      tester.view.physicalSize = Size(c.width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(c.scale)),
            child: child!,
          ),
          home: const InboxView(),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      rig.controller.applyFilter(
        const InboxFilter(wheres: ['me', 'allapprovals']),
      );
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(InboxCard), findsWidgets);
      for (
        var i = 0;
        i < 6 && find.byType(ApprovalCard).evaluate().isEmpty;
        i++
      ) {
        await tester.drag(find.byType(InboxCard).first, const Offset(0, -500));
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.byType(ApprovalCard), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('inbox-records-count')),
          matching: find.text('2'),
        ),
        findsOneWidget,
        reason: 'the pill counts records only',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an approval-only choice shows the cards and no record cards', (
    tester,
  ) async {
    final rig = InboxRig();
    addTearDown(rig.dispose);
    rig.routes['records.query'] = (_) => queryReply([record(1)]);
    rig.routes['req.list'] = (_) => {
      'requests': [raw(1), raw(2)],
      'total': 2,
      'hasMore': false,
    };
    Get.put(rig.controller);
    addTearDown(Get.reset);
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const InboxView(),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    rig.controller.applyFilter(const InboxFilter(wheres: ['approvals']));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(InboxCard), findsNothing);
    expect(find.byType(ApprovalCard), findsWidgets);
    expect(find.byKey(const ValueKey('inbox-records-count')), findsNothing);
    expect(Approval.pending, 'pending');
  });
}
