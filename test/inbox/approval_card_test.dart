import 'dart:async';

import 'package:connectum/core/theme/app_tones.dart';
import 'package:connectum/data/models/approval.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/inbox/models/approval_rules.dart';
import 'package:connectum/features/inbox/widgets/approval_card.dart';
import 'package:connectum/features/inbox/widgets/approval_reason_sheet.dart';
import 'package:connectum/features/inbox/widgets/approval_filter_bar.dart';
import 'package:connectum/features/inbox/widgets/approvals_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';
import 'inbox_support.dart';

Approval ap(
  int id, {
  String type = 'submission',
  String status = Approval.pending,
  bool canRespond = true,
  String direction = Approval.incoming,
  String caption = 'Expense claim',
  List<ApprovalLine> lines = const [ApprovalLine('Amount', '120')],
  int? stage = 1,
  int? stages = 2,
}) => Approval(
  id: id,
  type: type,
  status: status,
  canRespond: canRespond,
  direction: direction,
  from: 'rhea',
  fromName: 'Rhea Rao',
  createdTs: DateTime(2026, 11, 20, 9, 30).millisecondsSinceEpoch,
  caption: caption,
  message: 'Rhea wants in',
  lines: lines,
  stage: stage,
  stages: stages,
  approvers: const ['ana'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;

  setUp(() => rig = InboxRig());
  tearDown(() => rig.dispose());

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: c!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  ApprovalCard card(Approval a) =>
      ApprovalCard(controller: rig.controller.approvals, request: a);

  group('per kind', () {
    final kinds = {
      'onboarding': 'Sign-up',
      'membership': 'Connection request',
      'associate': 'Connection request',
      'handover': 'Introduction',
      'group_invite': 'Group invitation',
      'host_transfer': 'Transfer',
      'whatever': 'Request',
    };
    for (final e in kinds.entries) {
      testWidgets('${e.key} is titled ${e.value}', (tester) async {
        await pump(tester, card(ap(1, type: e.key)));
        expect(find.text(e.value), findsOneWidget);
        expect(find.text('Waiting for you'), findsOneWidget);
        expect(find.text('Approve'), findsOneWidget);
        expect(find.text('Decline'), findsOneWidget);
        expect(find.text('Return'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a form shows its name, summary answers and step, and Return', (
      tester,
    ) async {
      await pump(tester, card(ap(1)));
      expect(find.text('Expense claim'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('Step 1 of 2'), findsOneWidget);
      expect(find.text('Return'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
    });
  });

  group('per state', () {
    testWidgets('waiting for approval: no buttons', (tester) async {
      await pump(
        tester,
        card(ap(1, canRespond: false, direction: Approval.outgoing)),
      );
      expect(find.text('Waiting for approval'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('declined', (tester) async {
      await pump(tester, card(ap(1, status: 'rejected', canRespond: false)));
      expect(find.text('Declined'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('approved', (tester) async {
      await pump(tester, card(ap(1, status: 'accepted', canRespond: false)));
      expect(find.text('Approved'), findsOneWidget);
    });

    testWidgets('closed has no tag and no buttons', (tester) async {
      await pump(tester, card(ap(1, status: 'ignored', canRespond: false)));
      expect(find.text('Waiting for you'), findsNothing);
      expect(find.text('Declined'), findsNothing);
      expect(find.text('Approve'), findsNothing);
    });
  });

  group('the new card', () {
    Finder circle() => find.byKey(const ValueKey('inbox-status-circle'));
    Color? circleColor(WidgetTester tester) =>
        (tester.widget<Container>(circle()).decoration as BoxDecoration).color;

    testWidgets('the circle carries the state colour and its word', (
      tester,
    ) async {
      final cases = <(Approval, AppTone, String)>[
        (ap(1), AppTones.yellow, 'Waiting for you'),
        (
          ap(2, canRespond: false, direction: Approval.outgoing),
          AppTones.violet,
          'Waiting for approval',
        ),
        (
          ap(3, status: 'accepted', canRespond: false),
          AppTones.green,
          'Approved',
        ),
        (
          ap(4, status: 'rejected', canRespond: false),
          AppTones.red,
          'Declined',
        ),
        (
          ap(5, status: 'ignored', canRespond: false),
          AppTones.slate,
          'Dismissed',
        ),
      ];
      final handle = tester.ensureSemantics();
      for (final (a, tone, word) in cases) {
        await pump(tester, card(a));
        expect(circleColor(tester), tone.solid, reason: word);
        expect(find.bySemanticsLabel(RegExp(word)), findsWidgets, reason: word);
      }
      handle.dispose();
    });

    testWidgets('title, then the name, then #id, date and time', (
      tester,
    ) async {
      await pump(tester, card(ap(7)));
      final title = tester.getTopLeft(find.text('Expense claim')).dy;
      final name = tester.getTopLeft(find.text('Rhea Rao').first).dy;
      final sub = tester.getTopLeft(find.text('#7')).dy;
      expect(title, lessThan(name));
      expect(name, lessThan(sub));
    });

    testWidgets('no inner scrolling', (tester) async {
      await pump(tester, card(ap(1)));
      expect(
        find.descendant(
          of: find.byType(ApprovalCard),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
    });

    testWidgets('many lines expand and collapse', (tester) async {
      final lines = [
        for (var i = 1; i <= 8; i++) ApprovalLine('Item $i', 'v$i'),
      ];
      await pump(tester, card(ap(1, lines: lines)));
      expect(find.text('v8'), findsNothing);
      await tester.tap(find.textContaining('Show more'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('v8'), findsOneWidget);
      await tester.tap(find.text('Show less'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('v8'), findsNothing);
    });

    testWidgets('a form footer fits 320 px at text scale 1.5', (tester) async {
      await pump(tester, card(ap(1)), width: 320, scale: 1.5);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Return'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('buttons wait while an answer is on its way', (tester) async {
      final gate = Completer<Map<String, dynamic>>();
      rig.routes['req.respond'] = (args) => gate.future;
      await pump(tester, card(ap(1, type: 'associate')));
      final first = rig.controller.approvals.respond(
        ap(1, type: 'associate'),
        ApprovalAction.accept,
      );
      await tester.pump();
      expect(rig.controller.approvals.busy, contains(1));
      expect(
        await rig.controller.approvals.respond(
          ap(1, type: 'associate'),
          ApprovalAction.reject,
        ),
        isFalse,
      );
      gate.complete({
        'request': {'id': 1, 'type': 'associate', 'status': 'accepted'},
      });
      await tester.runAsync(settle);
      expect(rig.controller.approvals.busy, isEmpty);
      unawaited(first);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a refused answer keeps the card and its buttons', (
      tester,
    ) async {
      rig.routes['req.respond'] = (args) =>
          throw const SocketCallError('forbidden');
      await pump(tester, card(ap(1, type: 'associate')));
      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.runAsync(settle);
      await tester.pump();
      expect(rig.controller.approvals.leaving, isEmpty);
      expect(find.text('Approve'), findsOneWidget);
    });
  });

  testWidgets('every kind fits 320 px at text scale 1.5', (tester) async {
    for (final type in [
      'onboarding',
      'associate',
      'submission',
      'group_invite',
    ]) {
      await pump(tester, card(ap(1, type: type)), width: 320, scale: 1.5);
      expect(tester.takeException(), isNull, reason: type);
    }
  });

  testWidgets('Approve answers on one tap', (tester) async {
    rig.routes['req.respond'] = (args) => {
      'request': {
        'id': 1,
        'type': 'associate',
        'status': 'accepted',
        'canRespond': false,
      },
    };
    await pump(tester, card(ap(1, type: 'associate')));
    await tester.tap(find.text('Approve'));
    await tester.pump();
    await tester.runAsync(settle);
    expect(rig.argsOf('req.respond').single, {'id': 1, 'action': 'accept'});
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'Decline of a form opens the sheet; of a connection it does not',
    (tester) async {
      await pump(tester, card(ap(1)));
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(find.text('Decline request'), findsOneWidget);
      expect(find.text('Allow resubmission'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
      expect(rig.argsOf('req.respond'), isEmpty);
    },
  );

  group('the status strip', () {
    Finder strip() => find.byKey(const ValueKey('inbox-status-strip'));

    testWidgets('each state shows its words in the strip, no pill', (
      tester,
    ) async {
      final cases = <(Approval, String)>[
        (ap(1), 'Waiting for you'),
        (
          ap(2, canRespond: false, direction: Approval.outgoing),
          'Waiting for approval',
        ),
        (ap(3, status: 'accepted', canRespond: false), 'Approved'),
        (ap(4, status: 'rejected', canRespond: false), 'Declined'),
      ];
      for (final (a, word) in cases) {
        await pump(tester, card(a));
        expect(strip(), findsOneWidget, reason: word);
        expect(
          find.descendant(of: strip(), matching: find.text(word)),
          findsOneWidget,
        );
        expect(find.text(word), findsOneWidget, reason: 'only the strip');
      }
    });

    testWidgets('the strip is above the action buttons, below the rows', (
      tester,
    ) async {
      await pump(tester, card(ap(1)));
      final rows = tester.getTopLeft(find.text('Amount')).dy;
      final s = tester.getTopLeft(strip()).dy;
      final buttons = tester.getTopLeft(find.text('Approve')).dy;
      expect(rows, lessThan(s));
      expect(s, lessThan(buttons));
    });

    testWidgets('the circle sits at the right edge (no menu)', (tester) async {
      await pump(tester, card(ap(1)));
      final c = tester.getRect(
        find.byKey(const ValueKey('inbox-status-circle')),
      );
      final f = tester.getRect(find.byType(ApprovalCard));
      expect(f.right - c.right, lessThan(20));
    });

    testWidgets('golden: an approval card', (tester) async {
      await pump(
        tester,
        RepaintBoundary(key: const ValueKey('g'), child: card(ap(1))),
      );
      await expectLater(
        find.byKey(const ValueKey('g')),
        matchesGoldenFile('goldens/approval_card_polish.png'),
      );
    });
  });

  group('the reason sheet', () {
    Future<void> open(
      WidgetTester tester,
      Approval a,
      ApprovalAction action, {
      double width = 390,
      double scale = 1,
    }) async {
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => ApprovalReasonSheet.show(
              context,
              rig.controller.approvals,
              a,
              action,
            ),
            child: const Text('open'),
          ),
        ),
        width: width,
        scale: scale,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('the form decline sheet opens with Send and takes typing', (
      tester,
    ) async {
      await open(tester, ap(1), ApprovalAction.reject);
      Finder send() => find.text('Send');
      expect(send(), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'No receipt');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Return has no resubmission switch', (tester) async {
      await open(tester, ap(1), ApprovalAction.returnIt);
      expect(find.text('Return to sender'), findsOneWidget);
      expect(find.text('Allow resubmission'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('the switch starts off on a form decline', (tester) async {
      await open(tester, ap(1), ApprovalAction.reject);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('fits 320 px at text scale 1.5', (tester) async {
      await open(tester, ap(1), ApprovalAction.reject, width: 320, scale: 1.5);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).first, 'x' * 600);
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text.length, ApprovalRules.maxText);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the pane shows the shared empty state', (tester) async {
    rig.routes['records.query'] = (_) => queryReply([]);
    rig.controller.onInit();
    await tester.runAsync(settle);
    await pump(
      tester,
      SizedBox(
        height: 600,
        child: ApprovalsPane(controller: rig.controller.approvals),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('There are no approvals.'), findsOneWidget);
  });

  testWidgets('the pane: Filters popup with counts, 320 px', (tester) async {
    Map<String, dynamic> req(int id, String status, String type) => {
      'id': id,
      'type': type,
      'status': status,
      'from': 'rhea',
      'fromName': 'Rhea Rao',
      'approvers': ['ana'],
      'direction': 'incoming',
      'canRespond': status == 'pending',
      'createdTs': DateTime.now().millisecondsSinceEpoch,
    };
    rig.routes['records.query'] = (_) => queryReply([]);
    rig.routes['req.list'] = (_) => {
      'requests': [
        req(1, 'pending', 'associate'),
        req(2, 'accepted', 'handover'),
        req(3, 'ignored', 'group_invite'),
      ],
      'total': 3,
      'hasMore': false,
    };
    rig.controller.onInit();
    await tester.runAsync(settle);
    rig.controller.approvals.start();
    await tester.runAsync(settle);
    await pump(
      tester,
      SizedBox(
        height: 700,
        child: Column(
          children: [
            Builder(
              builder: (context) => TextButton(
                key: const ValueKey('approval-filters-button'),
                onPressed: () =>
                    ApprovalFilterPopup.show(context, rig.controller.approvals),
                child: const Text('filters'),
              ),
            ),
            Expanded(
              child: ApprovalsPane(controller: rig.controller.approvals),
            ),
          ],
        ),
      ),
      width: 320,
      scale: 1.5,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('approval-selected-all')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('approval-filters-button')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('All 2'), findsOneWidget);
    expect(find.text('Pending 1'), findsOneWidget);
    expect(find.text('Requests 2'), findsOneWidget);
    expect(find.text('Rejected 0'), findsOneWidget);
    expect(find.text('Closed 1'), findsNothing);
    await tester.tap(find.text('Pending 1'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Apply'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const ValueKey('approval-selected-status')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
