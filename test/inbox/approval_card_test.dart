import 'package:connectum/data/models/approval.dart';
import 'package:connectum/features/inbox/models/approval_rules.dart';
import 'package:connectum/features/inbox/widgets/approval_card.dart';
import 'package:connectum/features/inbox/widgets/approval_reason_sheet.dart';
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
}
