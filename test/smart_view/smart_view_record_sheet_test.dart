import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/models/sv_source.dart';
import 'package:connectum/data/smart_view/sv_prefs.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:connectum/features/smart_view/smart_view_view.dart';
import 'package:connectum/features/smart_view/widgets/sv_record_sheet.dart';
import 'package:connectum/features/tickets/ticket_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';
import 'sv_support.dart';

// Fakes only: no server, no phone (DevGuard is for the integration tests).

class _Connectivity extends ConnectivityService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {
    state.value = AppConnectivity.online;
  }

  @override
  void attachSocket(Rx<SocketState> socketState) {}
}

/// The local store: every call is counted, nothing is answered.
class _LocalStore extends GetxService implements SubmissionRepository {
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add('${invocation.memberName}');
    return null;
  }
}

class _Routes extends NavigatorObserver {
  final pushed = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route.settings.name);
  }
}

Future<void> pumpFor(WidgetTester tester, [int ms = 600]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

SvSource _source() => SvSource.tryParse({
  'name': 'tickets',
  'caption': 'Tickets',
  'owner': 'svcapcpw1ann',
  'status': {
    'field': 'stage',
    'final': ['Closed'],
    'statuses': ['Open', 'In progress', 'Closed'],
  },
  'fields': [
    {'caption': 'Title', 'name': 'title', 'type': 'text'},
    {'caption': 'Stage', 'name': 'stage', 'type': 'list'},
    {'caption': 'Area', 'name': 'area', 'type': 'list'},
    {'caption': 'Due', 'name': 'due', 'type': 'date'},
    {'caption': 'Hours', 'name': 'hours', 'type': 'number'},
    {'caption': 'Notes', 'name': 'notes', 'type': 'text'},
    {'caption': 'Owner team', 'name': 'team', 'type': 'text'},
    {'caption': 'Cost centre', 'name': 'cost', 'type': 'text'},
  ],
})!;

List<SvRow> _rows() => [
  for (var i = 0; i < 3; i++)
    SvRow.tryParse({
      'id': i + 1,
      'by': 'svcapcpw1ann',
      'byName': 'Ann Rao',
      'ts': 1794833216000 + i * 60000,
      'tstruct': 'tickets',
      'canEdit': true,
      'values': {
        'title': 'Ticket ${i + 1}',
        'stage': 'Open',
        'area': 'Delivery',
        'due': '2026-11-2$i',
        'hours': i + 1,
        'notes': 'Note-${i + 1}',
        'team': 'Team-${i + 1}',
        'cost': 'CC-${i + 1}',
        'secret': 'HIDDEN-VALUE-123',
      },
    }, isReceived: false)!,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SvRig rig;
  late SmartViewController c;
  late _LocalStore local;
  late _Routes routes;

  setUp(() {
    Get.reset();
    rig = SvRig();
    local = _LocalStore();
    routes = _Routes();
    Get.put<SmartViewRepository>(rig.repo);
    Get.put<TicketRepository>(rig.tickets);
    Get.put<SubmissionRepository>(local);
    Get.put<FormFileRepository>(FakeFiles());
    Get.put<ConnectivityService>(_Connectivity());
    c = SmartViewController(
      repo: rig.repo,
      tickets: rig.tickets,
      submissions: local,
      prefs: SmartViewPrefs(),
      newTicketDetail: (id) => TicketDetailController(
        ticketId: id,
        tickets: rig.tickets,
        files: Get.find<FormFileRepository>(),
        connectivity: Get.find<ConnectivityService>(),
      ),
    );
    c.current.value = _source();
    c.table.value = SvTable(_source())
      ..rows.assignAll(_rows())
      ..phase.value = SvPhase.ready;
  });

  tearDown(() {
    rig.tickets.onClose();
    rig.repo.onClose();
    Get.reset();
  });

  Future<void> pumpScreen(WidgetTester t) async {
    t.view.physicalSize = const Size(390 * 2, 2400 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorObservers: [routes],
        home: Scaffold(body: SmartViewContent(controller: c)),
      ),
    );
    await pumpFor(t, 300);
  }

  void expectDetails(WidgetTester t, {required int n}) {
    expect(find.text('Record details'), findsOneWidget);
    final sheet = find.byType(SvRecordSheetBody);
    for (final text in [
      'Ticket $n',
      'Open',
      'Delivery',
      'Note-$n',
      'Team-$n',
      'CC-$n',
      'Ann Rao',
      'Notes',
      'Owner team',
      'Cost centre',
      'No.',
      'By',
      'Submitted',
      'Hours',
    ]) {
      expect(
        find.descendant(of: sheet, matching: find.text(text)),
        findsWidgets,
        reason: text,
      );
    }
    expect(find.textContaining('HIDDEN-VALUE'), findsNothing);
    expect(
      find.descendant(of: sheet, matching: find.textContaining('Show all')),
      findsNothing,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Show less')),
      findsNothing,
    );
    expect(find.textContaining('not saved on this phone'), findsNothing);
    expect(local.calls, isEmpty);
    expect(rig.socket.count('submission.get'), 0);
    expect(rig.socket.count('record.actions'), 0);
    expect(routes.pushed.whereType<String>().where((r) => r != '/'), isEmpty);
  }

  testWidgets('a card tap opens the record sheet from memory, all fields', (
    t,
  ) async {
    await pumpScreen(t);
    expect(find.text('Note-2'), findsNothing);
    await t.tap(find.text('Ticket 2'));
    await pumpFor(t, 900);
    expectDetails(t, n: 2);
    expect(find.byType(SvRecordSheetBody), findsOneWidget);
  });

  testWidgets('a table row tap opens the same sheet', (t) async {
    c.mode.value = SvViewMode.table;
    await pumpScreen(t);
    await pumpFor(t, 300);
    await t.tap(find.text('Ann Rao').last);
    await pumpFor(t, 900);
    expectDetails(t, n: 3);
  });

  testWidgets('the sheet closes on a tap outside and the list is intact', (
    t,
  ) async {
    await pumpScreen(t);
    await t.tap(find.text('Ticket 1'));
    await pumpFor(t, 900);
    expect(find.text('Record details'), findsOneWidget);
    await t.tapAt(const Offset(195, 10));
    await pumpFor(t, 900);
    expect(find.text('Record details'), findsNothing);
    expect(find.text('Ticket 1'), findsOneWidget);
    expect(local.calls, isEmpty);
  });
}
