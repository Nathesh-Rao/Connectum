import 'package:connectum/core/widgets/app_button.dart';
import 'package:connectum/data/models/record_state.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late TicketRepository repo;
  late TicketDetailController c;

  Future<void> open(
    WidgetTester tester, {
    Map<String, dynamic> extra = const {},
  }) async {
    socket = FakeSocket()..goOnline();
    repo = TicketRepository(socket, FakeStore(user: 'ana'), FakeConversations())
      ..onInit();
    socket.answers[RecordCmd.get] = {
      'submission': {
        'id': 24,
        'tstruct': 'help_ticket',
        'by': 'ana',
        'values': {'title': 'Printer', 'stage': 'Open'},
      },
    };
    socket.answers[RecordCmd.actions] = {
      ...fixtureData('record_actions'),
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
  }

  Future<TicketActionForm> show(WidgetTester tester, String kind) async {
    tester.view.physicalSize = const Size(900, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final form = c.newForm(kind);
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

  AppButton button(WidgetTester tester) =>
      tester.widget<AppButton>(find.byType(AppButton).last);

  tearDown(() {
    c.onClose();
    repo.onClose();
  });

  group('status sheet', () {
    testWidgets('shows the statuses of the record and the optional fields', (
      tester,
    ) async {
      await open(tester);
      await show(tester, 'status');
      for (final s in ['Open', 'In progress', 'Done (final)']) {
        expect(find.text(s), findsOneWidget);
      }
      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('Completion'), findsOneWidget);
      expect(find.text('Hours worked'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Comments *'), findsNothing);
      expect(button(tester).onPressed, isNotNull);
    });

    testWidgets('required fields come from record.actions and block Send', (
      tester,
    ) async {
      await open(
        tester,
        extra: {
          'commentsRequired': true,
          'completionRequired': true,
          'hoursRequired': true,
          'filesRequired': true,
        },
      );
      await show(tester, 'status');
      expect(find.text('Comments *'), findsOneWidget);
      expect(find.text('Completion *'), findsOneWidget);
      expect(find.text('Hours worked *'), findsOneWidget);
      expect(find.text('Files *'), findsOneWidget);
      expect(button(tester).onPressed, isNull);
    });

    testWidgets('a disabled item shows its why and keeps the button off', (
      tester,
    ) async {
      await open(
        tester,
        extra: {
          'items': [
            {
              'id': 'status',
              'label': 'Update status',
              'enabled': false,
              'why': 'Only the person it is with can do this.',
            },
          ],
        },
      );
      await show(tester, 'status');
      expect(
        find.text('Only the person it is with can do this.'),
        findsOneWidget,
      );
      expect(button(tester).onPressed, isNull);
    });

    testWidgets('a stale answer keeps what was typed and says why', (
      tester,
    ) async {
      await open(tester);
      final form = await show(tester, 'status');
      await tester.enterText(
        find.widgetWithText(TextField, 'Add a comment'),
        'Called the technician',
      );
      await tester.tap(find.text('In progress'));
      await tester.pump();
      socket.answers[RecordCmd.status] = const SocketCallError(
        'stale',
        'This record was updated by someone else. Reload to see the latest.',
      );
      await tester.runAsync(() async {
        await c.submit(form);
        await _settle();
      });
      await tester.pump();
      expect(form.commentsText.value, 'Called the technician');
      expect(find.text('Called the technician'), findsOneWidget);
      expect(find.textContaining('updated by someone else'), findsOneWidget);
      expect(button(tester).onPressed, isNotNull);
    });

    testWidgets('the same sheet sends again after stale with a new id', (
      tester,
    ) async {
      await open(tester);
      final form = await show(tester, 'status');
      form.statusPick.value = 'In progress';
      socket.answers[RecordCmd.status] = const SocketCallError('stale', 'x');
      await tester.runAsync(() => c.submit(form));
      socket.answers[RecordCmd.status] = fixtureData('record_status_ok');
      await tester.runAsync(() => c.submit(form));
      expect(socket.count(RecordCmd.status), 2);
    });
  });

  group('send sheet', () {
    testWidgets('asks who, why and remarks; disabled until someone is chosen', (
      tester,
    ) async {
      await open(tester);
      final form = await show(tester, 'send');
      expect(find.text('Choose a person'), findsOneWidget);
      expect(find.text('Reason'), findsOneWidget);
      expect(find.text('Remarks'), findsOneWidget);
      expect(button(tester).onPressed, isNull);
      form.person.value = const RecordPerson(username: 'ben', name: 'Ben Iyer');
      await tester.pump();
      expect(find.text('Ben Iyer'), findsOneWidget);
      expect(button(tester).onPressed, isNotNull);
    });

    testWidgets('a refused send keeps who and why', (tester) async {
      await open(tester);
      final form = await show(tester, 'send');
      form.person.value = const RecordPerson(username: 'ben', name: 'Ben Iyer');
      form.reasonText.value = 'Needs the technician';
      socket.answers[RecordCmd.send] = const SocketCallError(
        'invalid',
        'It is already with them.',
      );
      await tester.runAsync(() => c.submit(form));
      await tester.pump();
      expect(find.text('It is already with them.'), findsOneWidget);
      expect(form.person.value!.username, 'ben');
      expect(form.reasonText.value, 'Needs the technician');
    });
  });
}
