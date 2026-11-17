import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/tickets/ticket_detail_binding.dart';
import 'package:connectum/features/tickets/ticket_detail_view.dart';
import 'package:connectum/features/tickets/tickets_controller.dart';
import 'package:connectum/features/tickets/widgets/tickets_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';
import 'ticket_fixtures.dart';

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A connectivity service that is online and has the lifecycle of a real
/// one, so `Get.put` accepts it.
class _Connectivity extends ConnectivityService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {
    state.value = AppConnectivity.online;
  }

  @override
  void attachSocket(Rx<SocketState> socketState) {}
}

/// A real [GetMaterialApp]: the list opens the record by route, the record
/// opens the status sheet and the send sheet. No typed `Get.toNamed<T>`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late TicketRepository repo;
  late TicketsController list;

  setUp(() {
    Get.reset();
    socket = FakeSocket()..goOnline();
    repo = Get.put(
      TicketRepository(socket, FakeStore(user: 'ana'), FakeConversations()),
    );
    Get.put<FormFileRepository>(FakeFiles());
    Get.put<ConnectivityService>(_Connectivity());
    socket.answers[RecordCmd.mine] = {
      'submissions': [
        {
          'id': 24,
          'tstruct': 'help_ticket',
          'by': 'rhea',
          'holder': 'ana',
          'ts': 5,
          'values': {'title': 'Printer is jammed', 'stage': 'Open'},
        },
      ],
      'structures': {
        'help_ticket': {
          'caption': 'Ticket',
          'fields': {'title': 'Title', 'stage': 'Stage'},
          'status': {
            'field': 'stage',
            'statuses': ['Open', 'In progress', 'Done'],
            'final': ['Done'],
          },
        },
      },
      'total': 1,
      'hasMore': false,
      'next': null,
    };
    socket.answers[RecordCmd.get] = {
      'submission': {
        'id': 24,
        'tstruct': 'help_ticket',
        'by': 'rhea',
        'holder': 'ana',
        'ts': 5,
        'values': {'title': 'Printer is jammed', 'stage': 'Open'},
      },
    };
    socket.answers[RecordCmd.actions] = fixtureData('record_actions');
    socket.answers[RecordCmd.history] = fixtureData('submission_history');
    list = TicketsController(tickets: repo, connectivity: FakeConnectivity());
  });

  tearDown(() {
    list.onClose();
    repo.onClose();
    Get.reset();
  });

  testWidgets('list -> record -> status sheet -> send sheet', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: '/list',
        getPages: [
          GetPage(
            name: '/list',
            page: () => Scaffold(body: TicketsPane(controller: list)),
          ),
          GetPage(
            name: AppRoutes.ticket,
            page: () => const TicketDetailView(),
            binding: TicketDetailBinding(),
          ),
        ],
      ),
    );
    await tester.runAsync(() async {
      list.onInit();
      await _settle();
    });
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Printer is jammed'), findsOneWidget);

    // List -> record, by route (untyped call).
    await tester.tap(find.text('Printer is jammed'));
    await tester.pump();
    await tester.runAsync(_settle);
    await tester.pump(const Duration(milliseconds: 600));
    expect(Get.currentRoute, AppRoutes.ticketOf(24));
    expect(find.text('Ticket'), findsWidgets);
    expect(find.text('Update status'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);

    // Record -> status sheet.
    await tester.tap(find.text('Update status'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('In progress'), findsWidgets);
    expect(find.text('Hours worked'), findsOneWidget);
    Navigator.of(tester.element(find.text('Hours worked'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Hours worked'), findsNothing);

    // Record -> send sheet.
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Choose a person'), findsOneWidget);
    expect(find.text('Remarks'), findsOneWidget);
  });
}
