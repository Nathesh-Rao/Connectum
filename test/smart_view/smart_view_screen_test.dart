import 'dart:async';

import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/smart_view/smart_view_commands.dart';
import 'package:connectum/data/smart_view/sv_prefs.dart';
import 'package:connectum/features/smart_view/widgets/smart_view_card.dart';
import 'package:connectum/features/smart_view/widgets/smart_view_table.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/forms/models/form_launch.dart';
import 'package:connectum/features/smart_view/models/smart_view_entry.dart';
import 'package:connectum/features/smart_view/smart_view_binding.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:connectum/features/smart_view/smart_view_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';
import 'sv_support.dart';

const _rows = 'submissions.list';
const _mine = 'records.mine';
const _one = 'submission.get';

class _Submissions extends GetxService implements SubmissionRepository {
  StructureOpen answer = const StructureOpen('tickets', 'user', 'Tickets');
  final asked = <String>[];

  @override
  Future<StructureOpen> openStructure(String typed) async {
    asked.add(typed);
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connectivity extends ConnectivityService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {
    state.value = AppConnectivity.online;
  }

  @override
  void attachSocket(Rx<SocketState> socketState) {}
}

/// Bounded pumps: never pumpAndSettle (a loader or a spring may never stop).
Future<void> pumpFor(WidgetTester tester, [int ms = 600]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SvRig rig;
  late _Submissions submissions;
  final opened = <String>[];
  FormLaunch? launch;
  var formResult = true;

  /// Built inside the test, so every future runs on the test's clock.
  void init() {
    Get.reset();
    rig = SvRig();
    rig.socket.answers[SvCmd.sources] = captured('004');
    rig.socket.answers['record.actions'] = captured('030');
    submissions = _Submissions();
    Get.put<SmartViewRepository>(rig.repo);
    Get.put<TicketRepository>(rig.tickets);
    Get.put<SubmissionRepository>(submissions);
    Get.put<FormFileRepository>(FakeFiles());
    Get.put<ConnectivityService>(_Connectivity());
    opened.clear();
    launch = null;
    formResult = true;
  }

  /// A widget test that starts with a fresh rig.
  void screenTest(
    String name,
    Future<void> Function(WidgetTester tester) body,
  ) => testWidgets(name, (tester) async {
    init();
    await body(tester);
  });

  tearDown(() {
    rig.tickets.onClose();
    rig.repo.onClose();
    Get.reset();
  });

  Future<void> boot(WidgetTester tester, String name) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    SmartViewBinding().dependencies();
    await tester.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        home: const SmartViewView(),
        getPages: [
          GetPage(
            name: AppRoutes.ticket,
            page: () {
              opened.add('ticket ${Get.parameters['id']}');
              return const Scaffold(body: Text('record screen'));
            },
          ),
          GetPage(
            name: AppRoutes.submissionDetail,
            page: () {
              opened.add('submission ${Get.parameters['id']}');
              return const Scaffold(body: Text('submission screen'));
            },
          ),
          GetPage(
            name: AppRoutes.form,
            page: () {
              launch = Get.arguments as FormLaunch?;
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Get.back<bool>(result: formResult),
                    child: const Text('save form'),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
    await tester.pump();
    unawaited(
      Get.find<SmartViewController>().enter(SmartViewEntry.named(name)),
    );
    await pumpFor(tester, 800);
  }

  void serve(
    List<Map<String, dynamic>> own, {
    List<Map<String, dynamic>> with_ = const [],
  }) {
    rig.socket.answers[_rows] = listPager(own);
    rig.socket.answers[_mine] = minePager({'with': with_}, pageSize: 50);
  }

  screenTest('cards: title, number, who and when, own fields, count pill', (
    tester,
  ) async {
    serve([ownRow(2, ts: 1794833216651), ownRow(1, ts: 1794833216000)]);
    await boot(tester, 'tickets');
    expect(find.text('Tickets'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Row 2'), findsOneWidget);
    expect(find.text('Row 1'), findsOneWidget);
    expect(find.text('No. 2'), findsOneWidget);
    expect(find.textContaining('Ann Rao'), findsNWidgets(2));
    expect(find.byTooltip('Add a record'), findsNothing);
    expect(find.bySemanticsLabel('Add a record'), findsOneWidget);
    expect(rig.socket.calls.where((c) => c.action == _rows).length, 1);
  });

  screenTest('a hidden field never reaches the screen', (tester) async {
    rig.socket.answers[_rows] = (args) =>
        args['offset'] == 0 ? captured('007') : captured('008');
    rig.socket.answers[_mine] = {'submissions': <Object>[], 'hasMore': false};
    await boot(tester, 'tickets');
    expect(find.text('Printer jammed'), findsOneWidget);
    expect(find.textContaining('HIDDEN'), findsNothing);
    expect(find.textContaining('Internal note'), findsNothing);
  });

  screenTest('loading, then empty with Add', (tester) async {
    final gate = Completer<void>();
    serve(const []);
    rig.socket.held[_rows] = gate.future;
    await boot(tester, 'tickets');
    expect(find.text('There is nothing here yet'), findsNothing);
    expect(find.text('Row 1'), findsNothing);
    gate.complete();
    await pumpFor(tester);
    expect(find.text('There is nothing here yet'), findsOneWidget);
    expect(find.text('Add a record'), findsOneWidget);
    // The one Add is the state's; the floating button is not drawn twice.
    expect(find.bySemanticsLabel('Add a record'), findsOneWidget);
    await tester.tap(find.text('Add a record'));
    await pumpFor(tester);
    expect(submissions.asked, ['tickets']);
  });

  screenTest('error shows the message and Retry reads again', (tester) async {
    rig.socket.answers[_rows] = const SocketCallError('error', 'Server down.');
    await boot(tester, 'tickets');
    expect(find.text('Server down.'), findsOneWidget);
    serve([ownRow(1)]);
    await tester.tap(find.text('Retry'));
    await pumpFor(tester);
    expect(find.text('Row 1'), findsOneWidget);
    expect(find.text('Server down.'), findsNothing);
  });

  screenTest('offline: the offline state with Retry, no crash', (tester) async {
    rig.socket.goOffline();
    await boot(tester, 'tickets');
    expect(find.text('You are offline'), findsOneWidget);
    rig.socket.goOnline();
    serve([ownRow(1)]);
    await tester.tap(find.text('Retry'));
    await pumpFor(tester);
    expect(find.text('Row 1'), findsOneWidget);
  });

  screenTest('not_found is a calm "not available", never forbidden', (
    tester,
  ) async {
    rig.socket.answers[_rows] = const SocketCallError('not_found', 'No such.');
    await boot(tester, 'tickets');
    expect(find.text(SmartViewView.noAccessTitle), findsOneWidget);
    expect(find.text(SmartViewView.noAccessMessage), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  screenTest('a name nobody can open offers the list instead', (tester) async {
    await boot(tester, 'nothing_here');
    // No such structure: nothing is opened and the list is offered.
    expect(Get.find<SmartViewController>().isDrawerOpen.value, isTrue);
    expect(find.text('Tickets'), findsWidgets);
    expect(find.text('There is nothing here yet'), findsNothing);
  });

  screenTest('partial: rows show, a small line says more is coming', (
    tester,
  ) async {
    final gate = Completer<void>();
    final pager = listPager([for (var i = 700; i > 0; i--) ownRow(i)]);
    rig.socket.answers[_mine] = {'submissions': <Object>[], 'hasMore': false};
    rig.socket.answers[_rows] = (args) {
      rig.socket.held[_rows] = gate.future;
      return pager(args);
    };
    await boot(tester, 'tickets');
    expect(find.text('Row 700'), findsOneWidget);
    expect(find.text('Loading more…'), findsNothing); // below the fold
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    for (var i = 0; i < 6; i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
    }
    expect(find.text('Loading more…'), findsOneWidget);
    gate.complete();
    await pumpFor(tester, 800);
    expect(find.text('Loading more…'), findsNothing);
    expect(rig.socket.calls.where((c) => c.action == _rows).length, 2);
  });

  screenTest('a page that failed offers Retry under the cards', (tester) async {
    final pager = listPager([for (var i = 600; i > 0; i--) ownRow(i)]);
    rig.socket.answers[_mine] = {'submissions': <Object>[], 'hasMore': false};
    rig.socket.answers[_rows] = (args) {
      if (args['offset'] == 500) throw const SocketCallError('error', 'x');
      return pager(args);
    };
    await boot(tester, 'tickets');
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    for (var i = 0; i < 6; i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
    }
    expect(find.text('Not everything loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  screenTest('a record with a status opens the record screen, a plain one the '
      'submission view, a received one the record screen', (tester) async {
    serve([ownRow(5)], with_: [mineRow(6)]);
    await boot(tester, 'tickets');
    await tester.tap(find.text('Row 5'));
    await pumpFor(tester);
    expect(opened, ['ticket 5']);
    Get.back<void>();
    await pumpFor(tester);
    await tester.tap(find.text('Received 6'));
    await pumpFor(tester);
    expect(opened, ['ticket 5', 'ticket 6']);
  });

  screenTest('a structure with no status opens the submission view', (
    tester,
  ) async {
    rig.socket.answers[SvCmd.sources] = {
      'forms': [
        {
          'name': 'plain',
          'caption': 'Plain',
          'canFetch': true,
          'canAdd': true,
          'fields': [
            {'name': 'title', 'caption': 'Title', 'type': 'text'},
          ],
          'status': null,
        },
      ],
    };
    serve([ownRow(8, tstruct: 'plain')]);
    await boot(tester, 'plain');
    await tester.tap(find.text('Row 8'));
    await pumpFor(tester);
    expect(opened, ['submission 8']);
  });

  screenTest('Add opens the structure form and the saved record shows', (
    tester,
  ) async {
    serve([ownRow(1)]);
    await boot(tester, 'tickets');
    await tester.tap(find.bySemanticsLabel('Add a record'));
    await pumpFor(tester);
    expect(submissions.asked, ['tickets']);
    expect(launch?.name, 'tickets');
    expect(launch?.convId, isNull);
    serve([ownRow(9, ts: 99999999), ownRow(1)]);
    await tester.tap(find.text('save form'));
    await pumpFor(tester, 1600);
    expect(find.text('Row 9'), findsOneWidget);
    expect(find.text('Row 1'), findsOneWidget);
    expect(find.text('save form'), findsNothing);
  });

  screenTest('Add that is cancelled changes nothing', (tester) async {
    serve([ownRow(1)]);
    await boot(tester, 'tickets');
    formResult = false;
    final before = rig.socket.calls.length;
    await tester.tap(find.bySemanticsLabel('Add a record'));
    await pumpFor(tester);
    await tester.tap(find.text('save form'));
    await pumpFor(tester, 1600);
    expect(rig.socket.calls.length, before);
  });

  screenTest('a live status change shows in place, no command (data.record)', (
    tester,
  ) async {
    serve([ownRow(1)]);
    await boot(tester, 'tickets');
    final before = rig.socket.calls.length;
    rig.repo.onEvent({
      'type': 'sd_event',
      'event': 'submissions_changed',
      'data': {
        'id': 1,
        'tstruct': 'tickets',
        'action': 'Status update',
        'record': {
          'by': 'svcapcpw1ann',
          'claimants': <String>[],
          'completion': 40,
          'final': false,
          'holder': 'svcapcpw1bob',
          'status': 'In progress',
          'ts': 5,
        },
      },
    });
    await pumpFor(tester, 800);
    expect(find.text('In progress'), findsOneWidget);
    expect(
      rig.socket.calls.skip(before).where((c) => c.action == _one),
      isEmpty,
    );
  });

  screenTest('a live event without data.record reads that record once', (
    tester,
  ) async {
    serve([ownRow(1)]);
    await boot(tester, 'tickets');
    rig.socket.answers[_one] = {
      'submission': ownRow(
        7,
        ts: 99999999,
        values: {'title': 'Fresh', 'stage': 'Open'},
      ),
    };
    rig.repo.onEvent({
      'type': 'sd_event',
      'event': 'submissions_changed',
      'data': {'id': 7, 'tstruct': 'tickets', 'action': 'created'},
    });
    await pumpFor(tester, 800);
    expect(find.text('Fresh'), findsOneWidget);
    expect(rig.socket.calls.where((c) => c.action == _one).length, 1);
  });

  screenTest('pull to refresh reads the lists again', (tester) async {
    serve([ownRow(1)]);
    await boot(tester, 'tickets');
    serve([ownRow(2, ts: 99999999), ownRow(1)]);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await pumpFor(tester, 1500);
    expect(find.text('Row 2'), findsOneWidget);
  });

  group('cards and table', () {
    screenTest('cards by default, the switch changes to the table without '
        'reading again, and the choice is saved', (tester) async {
      final written = <String>[];
      Get.put(SmartViewPrefs(write: (v) async => written.add(v)));
      serve([ownRow(2), ownRow(1)]);
      await boot(tester, 'tickets');
      expect(find.byType(SmartViewCard), findsWidgets);
      expect(find.byType(SmartViewTable), findsNothing);
      final calls = rig.socket.calls.length;
      await tester.tap(find.bySemanticsLabel('Table'));
      await pumpFor(tester, 500);
      expect(find.byType(SmartViewTable), findsOneWidget);
      expect(find.byType(SmartViewCard), findsNothing);
      expect(written, ['table']);
      expect(rig.socket.calls.length, calls, reason: 'nothing is read again');
      await tester.tap(find.bySemanticsLabel('Cards'));
      await pumpFor(tester, 500);
      expect(find.byType(SmartViewCard), findsWidgets);
      expect(rig.socket.calls.length, calls);
      expect(written, ['table', 'cards']);
    });

    screenTest('a saved table choice is the first thing drawn', (tester) async {
      Get.put(SmartViewPrefs(mode: SvViewMode.table));
      serve([ownRow(2), ownRow(1)]);
      await boot(tester, 'tickets');
      expect(find.byType(SmartViewTable), findsOneWidget);
      expect(find.byType(SmartViewCard), findsNothing);
    });

    screenTest('golden: the cards list', (tester) async {
      serve([
        ownRow(
          3,
          ts: 1794833216938,
          values: {
            'title': 'Printer jammed',
            'stage': 'Open',
            'area': 'Delivery',
            'due': '2026-11-20',
          },
        ),
        ownRow(
          2,
          ts: 1794833216651,
          values: {'title': 'Invoice mismatch', 'stage': 'In progress'},
        ),
      ]);
      await boot(tester, 'tickets');
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_cards_list.png'),
      );
    });
  });

  group('goldens', () {
    Future<void> shot(WidgetTester tester, String name) async {
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    }

    screenTest('list: loaded', (tester) async {
      serve(
        [
          ownRow(
            3,
            ts: 1794833216938,
            values: {
              'title': 'Printer jammed',
              'stage': 'Open',
              'area': 'Delivery',
            },
          ),
          ownRow(
            2,
            ts: 1794833216651,
            values: {
              'title': 'Invoice mismatch',
              'stage': 'In progress',
              'area': 'Billing',
            },
          ),
        ],
        with_: [mineRow(1, ts: 1794833216000)],
      );
      await boot(tester, 'tickets');
      await shot(tester, 'sv_list_loaded');
    });

    screenTest('list: loading', (tester) async {
      final gate = Completer<void>();
      serve(const []);
      rig.socket.held[_rows] = gate.future;
      await boot(tester, 'tickets');
      await shot(tester, 'sv_list_loading');
      gate.complete();
      await pumpFor(tester);
    });

    screenTest('list: empty', (tester) async {
      serve(const []);
      await boot(tester, 'tickets');
      await shot(tester, 'sv_list_empty');
    });

    screenTest('list: error', (tester) async {
      rig.socket.answers[_rows] = const SocketCallError(
        'error',
        'Server down.',
      );
      await boot(tester, 'tickets');
      await shot(tester, 'sv_list_error');
    });
  });

  test('the colours of the goldens are the white scaffold', () {
    expect(AppColors.white, const Color(0xFFFFFFFF));
  });
}
