import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/approval_repository.dart';
import 'package:connectum/data/repositories/feed_repository.dart';
import 'package:connectum/data/repositories/inbox_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/socket/read_gate.dart';
import 'package:connectum/features/tickets/record_detail_view.dart';
import 'package:connectum/features/tickets/ticket_detail_controller.dart';
import 'package:connectum/features/tickets/widgets/record_detail_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../inbox/inbox_support.dart';
import '../support/fake_socket.dart';

const _fileId = 'aaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> _form({bool hasStatus = true}) => {
  'caption': hasStatus ? 'Help ticket' : 'Leave note',
  'fields': {
    'title': 'Title',
    'owner': 'Owner',
    'due': 'Due date',
    'attach': 'Attachment',
  },
  if (hasStatus)
    'status': {
      'field': 'stage',
      'statuses': ['Open', 'In progress', 'Done'],
      'final': ['Done'],
    },
};

Map<String, dynamic> _sub(
  int id, {
  String by = 'rhea',
  String? status,
  Map<String, dynamic>? values,
}) => {
  'id': id,
  'tstruct': 'f',
  'by': by,
  'holder': 'ana',
  'ts': 1764000000000,
  'status': ?status,
  'values':
      values ??
      {
        'title': 'Printer is jammed',
        'owner': 'rhea',
        'due': '2026-11-30',
        'attach': [_fileId],
        'stage': 'Open',
      },
};

Map<String, dynamic> _card(
  int id, {
  bool hasStatus = true,
  String by = 'rhea',
  String? status,
}) => {
  'submissions': [
    {
      ..._sub(id, by: by, status: status),
      'files': {
        'attach': [
          {'id': _fileId, 'name': 'invoice.pdf', 'size': 2048, 'ext': 'pdf'},
        ],
      },
    },
  ],
  'structures': {'f': _form(hasStatus: hasStatus)},
  'total': 1,
};

Map<String, dynamic> _actions({bool hasMenu = true, String status = 'Open'}) =>
    {
      'holder': 'ana',
      'initiator': 'rhea',
      'isAdmin': false,
      'final': ['Done'],
      'status': status,
      'statuses': status.isEmpty ? <String>[] : ['Open', 'In progress', 'Done'],
      'items': hasMenu
          ? [
              {'id': 'send', 'label': 'Send', 'enabled': true},
              {'id': 'status', 'label': 'Update status', 'enabled': true},
            ]
          : <Map<String, dynamic>>[],
    };

Map<String, dynamic> _request(int id, {required int record}) => {
  'id': id,
  'type': 'submission',
  'status': 'pending',
  'from': 'rhea',
  'approvers': ['ana'],
  'direction': 'incoming',
  'canRespond': true,
  'createdTs': 1000,
  'submissionId': record,
};

class _Bind extends Bindings {
  _Bind(this.c);

  final TicketDetailController c;

  @override
  void dependencies() {
    Get.put(c, tag: '${c.ticketId}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HeldSocket socket;
  late TicketRepository tickets;
  late InboxRepository inbox;
  late ApprovalRepository approvals;
  late FeedRepository feed;
  late TicketDetailController controller;

  Future<void> boot(
    WidgetTester tester,
    int id, {
    required Map<String, dynamic> sub,
    required Map<String, dynamic> card,
    required Map<String, dynamic> actions,
    String me = 'ana',
    List<Map<String, dynamic>> requests = const [],
    Size size = const Size(390, 844),
    double scale = 1,
    SocketCallError? gone,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    Get.reset();
    final clock = GateClock();
    socket = HeldSocket()..goOnline();
    final store = FakeStore(user: me);
    final gate = ReadGate(now: clock.read, delay: clock.delay);
    tickets = TicketRepository(socket, store, FakeConversations());
    inbox = InboxRepository(socket, store, gate)..onInit();
    feed = FeedRepository(socket, store, FakeE2e())..onInit();
    approvals = ApprovalRepository(socket, store, feed, gate: gate)..onInit();
    socket.handler = (action, args) async {
      switch (action) {
        case RecordCmd.get:
          if (gone != null) throw gone;
          return {'submission': sub};
        case RecordCmd.card:
          return card;
        case RecordCmd.actions:
          if (gone != null) throw gone;
          return actions;
        case RecordCmd.history:
          return {
            'caption': 'Help ticket',
            'events': [
              {
                'id': 1,
                'op': 'created',
                'by': 'rhea',
                'ts': DateTime.now().millisecondsSinceEpoch,
              },
            ],
            'names': {'rhea': 'Rhea Das'},
            'fields': {'title': 'Title'},
            'files': <String, dynamic>{},
          };
        case 'people.cards':
          return {
            'people': {
              'rhea': {'name': 'Rhea Das'},
            },
          };
        case 'req.list':
          return {
            'requests': requests,
            'total': requests.length,
            'hasMore': false,
          };
        case 'req.respond':
          return {
            'request': {...requests.first, 'status': 'accepted'},
          };
      }
      return <String, dynamic>{};
    };
    controller = TicketDetailController(
      ticketId: id,
      tickets: tickets,
      files: FakeFiles(),
      connectivity: FakeConnectivity(),
      inbox: inbox,
      approvals: approvals,
    );
    await tester.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        initialRoute: AppRoutes.ticketOf(id),
        getPages: [
          GetPage(
            name: AppRoutes.ticket,
            page: () => const RecordDetailView(),
            binding: _Bind(controller),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.runAsync(settle);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  tearDown(() {
    tickets.onClose();
    feed.onClose();
    Get.reset();
  });

  testWidgets('a ticket: kind title, strip, typed fields, menu, history', (
    tester,
  ) async {
    await boot(tester, 24, sub: _sub(24), card: _card(24), actions: _actions());
    expect(tester.takeException(), isNull);
    expect(find.text('Ticket #24'), findsOneWidget);
    expect(find.text('Rhea Das'), findsWidgets);
    expect(find.byKey(const ValueKey('inbox-status-strip')), findsOneWidget);
    expect(find.text('Open'), findsWidgets);
    expect(find.byKey(const ValueKey('record-fields-card')), findsOneWidget);
    expect(find.text('Due date'), findsOneWidget);
    expect(find.text('30 Nov 2026'), findsOneWidget);
    expect(find.text('Update status'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
    // The one record read asks for the file details.
    final card = socket.calls.firstWhere((c) => c.action == RecordCmd.card);
    expect(card.args['fileMeta'], 2);
  });

  testWidgets('files show as chips with name and size, never the id', (
    tester,
  ) async {
    await boot(tester, 24, sub: _sub(24), card: _card(24), actions: _actions());
    expect(find.textContaining('invoice'), findsWidgets);
    expect(find.textContaining(_fileId), findsNothing);
  });

  testWidgets('files without details fall back to "1 file"', (tester) async {
    final card = _card(24);
    ((card['submissions'] as List).first as Map).remove('files');
    await boot(tester, 24, sub: _sub(24), card: card, actions: _actions());
    expect(find.text('1 file'), findsOneWidget);
    expect(find.textContaining(_fileId), findsNothing);
  });

  testWidgets('a submission: its own title, no menu, Edit for its author', (
    tester,
  ) async {
    await boot(
      tester,
      31,
      sub: _sub(31, by: 'ana'),
      card: _card(31, hasStatus: false, by: 'ana'),
      actions: _actions(hasMenu: false, status: ''),
    );
    expect(find.text('Submission #31'), findsOneWidget);
    expect(find.text('Ticket #31'), findsNothing);
    expect(find.text('Update status'), findsNothing);
    expect(find.text('Send'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
  });

  testWidgets('an approval: answers in the sticky bar, no Edit', (
    tester,
  ) async {
    await boot(
      tester,
      41,
      sub: _sub(41, by: 'rhea', status: 'pending'),
      card: _card(41, hasStatus: false, status: 'pending'),
      actions: _actions(hasMenu: false, status: ''),
      requests: [_request(7, record: 41)],
    );
    expect(find.text('Approval #41'), findsOneWidget);
    expect(find.text('Waiting for approval'), findsWidgets);
    expect(find.byKey(const ValueKey('record-action-bar')), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Return'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);

    await tester.tap(find.text('Approve'));
    await tester.pump();
    await tester.runAsync(settle);
    await tester.pump(const Duration(milliseconds: 300));
    final sent = socket.calls.firstWhere((c) => c.action == 'req.respond');
    expect(sent.args['id'], 7);
    expect(sent.args['action'], 'accept');
  });

  testWidgets('declining an approval asks for the reason first', (
    tester,
  ) async {
    await boot(
      tester,
      41,
      sub: _sub(41, status: 'pending'),
      card: _card(41, hasStatus: false, status: 'pending'),
      actions: _actions(hasMenu: false, status: ''),
      requests: [_request(7, record: 41)],
    );
    await tester.tap(find.text('Decline'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Decline request'), findsOneWidget);
    expect(socket.calls.where((c) => c.action == 'req.respond'), isEmpty);
    await tester.enterText(find.byType(TextField).first, 'Missing receipt');
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.runAsync(settle);
    await tester.pump(const Duration(milliseconds: 500));
    final sent = socket.calls.firstWhere((c) => c.action == 'req.respond');
    expect(sent.args['action'], 'reject');
    expect(sent.args['reason'], 'Missing receipt');
  });

  testWidgets('a gone record says so; no bar', (tester) async {
    await boot(
      tester,
      9,
      sub: _sub(9),
      card: _card(9),
      actions: _actions(),
      gone: const SocketCallError('not_found'),
    );
    expect(find.text('Ticket not available'), findsOneWidget);
    expect(find.byKey(const ValueKey('record-action-bar')), findsNothing);
  });

  testWidgets('loading shows the skeleton', (tester) async {
    await boot(tester, 24, sub: _sub(24), card: _card(24), actions: _actions());
    controller.ticket.value = null;
    controller.viewState.value = AppViewState.loading;
    await tester.pump();
    expect(find.byType(RecordDetailSkeleton), findsOneWidget);
  });

  for (final size in const [Size(320, 568)]) {
    testWidgets('fits $size at 1.5x text', (tester) async {
      await boot(
        tester,
        41,
        sub: _sub(41, status: 'pending'),
        card: _card(41, hasStatus: false, status: 'pending'),
        actions: _actions(hasMenu: false, status: ''),
        requests: [_request(7, record: 41)],
        size: size,
        scale: 1.5,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Approve'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
