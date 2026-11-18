import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/tickets/ticket_action_form.dart';
import 'package:connectum/features/tickets/ticket_detail_controller.dart';
import 'package:connectum/features/tickets/widgets/ticket_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';
import 'ticket_fixtures.dart';

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _warning =
    'Closing this ticket sets completion to 100%. After it is closed, only an administrator can change it.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late TicketRepository repo;
  late TicketDetailController c;

  Future<TicketActionForm> show(
    WidgetTester tester, {
    Map<String, dynamic> extra = const {},
    Size size = const Size(900, 3200),
  }) async {
    socket = FakeSocket()..goOnline();
    repo = TicketRepository(socket, FakeStore(user: 'ana'), FakeConversations())
      ..onInit();
    socket.answers[RecordCmd.get] = {
      'submission': {
        'id': 24,
        'tstruct': 'help_ticket',
        'by': 'ana',
        'values': {'title': 'Printer', 'stage': 'In progress'},
      },
    };
    socket.answers[RecordCmd.actions] = {
      ...fixtureData('record_actions'),
      'status': 'In progress',
      'completion': 40,
      ...extra,
    };
    socket.answers[RecordCmd.history] = fixtureData('submission_history');
    c = TicketDetailController(
      ticketId: 24,
      tickets: repo,
      files: FakeFiles(),
      connectivity: FakeConnectivity(),
      busyDelay: Duration.zero,
    )..onInit();
    await tester.runAsync(_settle);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final form = c.newForm('status');
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TicketActionSheet(controller: c, form: form),
          ),
        ),
      ),
    );
    await tester.pump();
    return form;
  }

  Future<void> pick(WidgetTester tester, TicketActionForm f, String n) async {
    f.pickStatus(n);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  double sliderValue(WidgetTester tester) =>
      tester.widget<Slider>(find.byType(Slider)).value;

  tearDown(() {
    c.onClose();
    repo.onClose();
  });

  testWidgets('starts at the completion the record has', (tester) async {
    final f = await show(tester);
    expect(f.percent.value, 40);
    expect(sliderValue(tester), 40);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('Not set'), findsNothing);
    expect(find.text('Was 40%'), findsOneWidget);
    expect(find.text(_warning), findsNothing);
  });

  testWidgets('Not set only when the record has no completion', (tester) async {
    final f = await show(tester, extra: {'completion': null});
    expect(f.percent.value, isNull);
    expect(find.text('Not set'), findsOneWidget);
    expect(find.textContaining('Was'), findsNothing);
  });

  testWidgets('a person cannot slide below the previous value', (tester) async {
    final handle = tester.ensureSemantics();
    final f = await show(tester);
    await tester.drag(find.byType(Slider), const Offset(-600, 0));
    await tester.pump();
    expect(f.percent.value, greaterThanOrEqualTo(40));
    f.setPercent(10);
    expect(f.percent.value, 40);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(
      slider.semanticFormatterCallback!(40),
      'Completion 40 percent, minimum 40',
    );
    expect(
      find.bySemanticsLabel('Completion is locked below 40 percent'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('an administrator can go lower, with no lock shown', (
    tester,
  ) async {
    final f = await show(tester, extra: {'isAdmin': true});
    expect(find.textContaining('Was'), findsNothing);
    f.setPercent(10);
    await tester.pump();
    expect(f.percent.value, 10);
    expect(sliderValue(tester), 10);
  });

  testWidgets('a final status sets 100, locks the slider, warns', (
    tester,
  ) async {
    final f = await show(tester);
    await pick(tester, f, 'Done');
    expect(f.percent.value, 100);
    expect(sliderValue(tester), 100);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    expect(find.text(_warning), findsOneWidget);
    f.setPercent(50);
    expect(f.percent.value, 100);
  });

  testWidgets('a non-final status caps the slider at 99, never closes', (
    tester,
  ) async {
    final f = await show(tester);
    f.setPercent(100);
    await tester.pump();
    expect(f.percent.value, 99);
    expect(f.statusPick.value, 'In progress');
    await tester.drag(find.byType(Slider), const Offset(900, 0));
    await tester.pump();
    expect(f.percent.value, 99);
    expect(f.statusPick.value, 'In progress');
    expect(find.text(_warning), findsNothing);
  });

  testWidgets('finalStatuses keep the form order, not sorted', (tester) async {
    final f = await show(
      tester,
      extra: {
        'statuses': ['Open', 'In progress', 'Closed', 'Dropped'],
        'finalStatuses': ['Dropped', 'Closed'],
      },
    );
    expect(f.state.finalStatuses, ['Dropped', 'Closed']);
    await pick(tester, f, 'Dropped');
    expect(f.percent.value, 100);
    expect(f.isPercentLocked, isTrue);
    await pick(tester, f, 'Closed');
    expect(f.percent.value, 100);
  });

  testWidgets('a member cannot go below minCompletion or the current value', (
    tester,
  ) async {
    final f = await show(tester, extra: {'minCompletion': 55});
    expect(f.minPercent, 55);
    f.setPercent(10);
    expect(f.percent.value, 55);
  });

  testWidgets('the current completion wins over a lower minCompletion', (
    tester,
  ) async {
    final f = await show(tester, extra: {'minCompletion': 10});
    expect(f.minPercent, 40);
  });

  testWidgets('an administrator goes below, to 0', (tester) async {
    final f = await show(tester, extra: {'isAdmin': true, 'minCompletion': 0});
    expect(f.minPercent, 0);
    f.setPercent(0);
    expect(f.percent.value, 0);
  });

  testWidgets('an older record at 100 on a non-final status is fixed', (
    tester,
  ) async {
    final f = await show(
      tester,
      extra: {'completion': 100, 'minCompletion': 100},
    );
    expect(f.isPercentFixed, isTrue);
    expect(f.percent.value, 100);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    f.setPercent(50);
    expect(f.percent.value, 100);
    expect(f.statusInput.percent, isNull);
  });

  testWidgets('a non-final status never keeps 100', (tester) async {
    final f = await show(tester);
    await pick(tester, f, 'Open');
    expect(f.percent.value, 40);
    f.setPercent(100);
    expect(f.statusPick.value, 'Open');
    expect(f.percent.value, 99);
  });

  testWidgets('final to non-final restores the previous completion', (
    tester,
  ) async {
    final f = await show(tester);
    await pick(tester, f, 'Done');
    await pick(tester, f, 'In progress');
    expect(f.percent.value, 40);
    expect(find.text(_warning), findsNothing);
  });

  testWidgets('reopening a closed record as admin presets 99 and says so', (
    tester,
  ) async {
    final f = await show(
      tester,
      extra: {'isAdmin': true, 'status': 'Done', 'completion': 100},
    );
    expect(f.percent.value, 100);
    expect(find.text(_warning), findsOneWidget);
    expect(find.text('Reopening sets completion to 99%'), findsNothing);
    await pick(tester, f, 'Open');
    expect(f.percent.value, 99);
    expect(find.text('Reopening sets completion to 99%'), findsOneWidget);
    expect(f.statusInput.percent, 99);
    f.setPercent(70);
    await tester.pump();
    expect(find.text('Reopening sets completion to 99%'), findsNothing);
  });

  testWidgets('no final status in the form keeps the old behaviour', (
    tester,
  ) async {
    final f = await show(tester, extra: {'final': <String>[]});
    f.setPercent(100);
    await tester.pump();
    expect(f.statusPick.value, 'In progress');
    expect(f.percent.value, 100);
    await pick(tester, f, 'Done');
    expect(f.percent.value, 100);
    expect(find.text(_warning), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
  });

  testWidgets('the payload follows the final state of the sheet', (
    tester,
  ) async {
    final f = await show(tester);
    await pick(tester, f, 'Done');
    socket.answers[RecordCmd.status] = fixtureData('record_status_ok');
    await tester.runAsync(() => c.submit(f));
    final args = socket.calls
        .lastWhere((c) => c.action == RecordCmd.status)
        .args;
    expect(args['status'], 'Done');
    expect(args['percent'], 100);
  });

  testWidgets('a server refusal is still shown', (tester) async {
    final f = await show(tester);
    f.setPercent(60);
    socket.answers[RecordCmd.status] = const SocketCallError(
      'invalid',
      'Completion cannot go down.',
    );
    await tester.runAsync(() => c.submit(f));
    await tester.pump();
    expect(find.text('Completion cannot go down.'), findsOneWidget);
  });

  testWidgets('the 100%-only-for-closing refusal shows under the slider', (
    tester,
  ) async {
    final f = await show(tester);
    f.setPercent(60);
    const text =
        '100% completion is only for a closing status. Choose a closing status.';
    socket.answers[RecordCmd.status] = const SocketCallError('invalid', text);
    await tester.runAsync(() => c.submit(f));
    await tester.pump();
    expect(f.percentError.value, text);
    expect(f.error.value, isNull);
    expect(find.text(text), findsOneWidget);
    f.setPercent(70);
    expect(f.percentError.value, isNull);
  });

  testWidgets('text at 200% does not overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await show(tester, size: const Size(360, 3200));
    expect(tester.takeException(), isNull);
  });

  group('goldens', () {
    testWidgets('opened with previous 40%', (tester) async {
      await show(tester, size: const Size(420, 1500));
      await expectLater(
        find.byType(TicketActionSheet),
        matchesGoldenFile('goldens/status_sheet_previous_40.png'),
      );
    });

    testWidgets('final selected: 100% and the warning', (tester) async {
      final f = await show(tester, size: const Size(420, 1500));
      await pick(tester, f, 'Done');
      await expectLater(
        find.byType(TicketActionSheet),
        matchesGoldenFile('goldens/status_sheet_final.png'),
      );
    });

    testWidgets('administrator: free slider', (tester) async {
      await show(tester, extra: {'isAdmin': true}, size: const Size(420, 1500));
      await expectLater(
        find.byType(TicketActionSheet),
        matchesGoldenFile('goldens/status_sheet_admin.png'),
      );
    });
  });
}
