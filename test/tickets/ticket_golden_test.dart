import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/data/models/record_state.dart';
import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/features/tickets/ticket_detail_controller.dart';
import 'package:connectum/features/tickets/widgets/ticket_action_sheet.dart';
import 'package:connectum/features/tickets/widgets/ticket_history_timeline.dart';
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

/// Goldens of the screens the record flow added or changed: the status sheet
/// (required fields marked), the send sheet and the history timeline with
/// every kind of event.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TicketRepository repo;
  late TicketDetailController c;

  Future<void> open(
    WidgetTester tester, {
    Map<String, dynamic> extra = const {},
  }) async {
    final socket = FakeSocket()..goOnline();
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
    )..onInit();
    await tester.runAsync(_settle);
  }

  tearDown(() {
    c.onClose();
    repo.onClose();
  });

  Widget host(Widget child) => GetMaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: AppColors.white,
      body: RepaintBoundary(
        key: const ValueKey('shot'),
        child: ColoredBox(
          color: AppColors.white,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );

  testWidgets('status sheet with required fields', (tester) async {
    tester.view.physicalSize = const Size(420, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(
      tester,
      extra: {'commentsRequired': true, 'hoursRequired': true},
    );
    await tester.pumpWidget(
      host(TicketActionSheet(controller: c, form: c.newForm('status'))),
    );
    await tester.pump();
    await expectLater(
      find.byKey(const ValueKey('shot')),
      matchesGoldenFile('goldens/status_sheet.png'),
    );
  });

  testWidgets('send sheet', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester);
    await tester.pumpWidget(
      host(TicketActionSheet(controller: c, form: c.newForm('send'))),
    );
    await tester.pump();
    await expectLater(
      find.byKey(const ValueKey('shot')),
      matchesGoldenFile('goldens/send_sheet.png'),
    );
  });

  testWidgets('history timeline with every operation', (tester) async {
    tester.view.physicalSize = const Size(420, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final events = [
      for (var i = 0; i < RecordEvent.ops.length; i++)
        RecordEvent.tryParse({
          'id': i,
          'op': RecordEvent.ops[i],
          'by': 'ana',
          'ts': DateTime(2026, 11, 1, 9, i).millisecondsSinceEpoch,
          if (RecordEvent.ops[i] == 'sent') ...{
            'to': ['ben'],
            'via': 'user',
            'fromHolder': 'ana',
            'reason': 'Needs the technician',
          },
          if (RecordEvent.ops[i] == 'status') ...{
            'fromStatus': 'Open',
            'toStatus': 'In progress',
            'completion': '30',
            'hours': '2.5',
            'remarks': 'Technician called',
            'asAdmin': true,
          },
          if (RecordEvent.ops[i] == 'edited')
            'changes': [
              {'field': 'title', 'from': 'Printer', 'to': 'Printer 2'},
            ],
          if (RecordEvent.ops[i] == 'reassigned') 'to': ['sam'],
        })!,
    ];
    await tester.pumpWidget(
      host(
        TicketHistoryTimeline(
          feed: HistoryFeed(
            history: RecordHistory(
              events: events,
              names: const {
                'ana': 'Ana Rao',
                'ben': 'Ben Iyer',
                'sam': 'Sam Joseph',
              },
              fields: const {'title': 'Title'},
            ),
            nameOf: (u) => u,
            ticket: const Ticket(
              id: 24,
              by: 'ana',
              ts: 1,
              tstruct: 'help_ticket',
            ),
            first: 'Open',
            now: DateTime(2026, 11, 1, 12),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byKey(const ValueKey('shot')),
      matchesGoldenFile('goldens/history_timeline.png'),
    );
  });
}
