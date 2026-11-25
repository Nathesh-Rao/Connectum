import 'dart:convert';

import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/data/commands/command_reply.dart';
import 'package:connectum/data/models/form_definition.dart';
import 'package:connectum/data/models/form_submission.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/command_repository.dart';
import 'package:connectum/data/repositories/form_options_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/repositories/workspace_repository.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/home_shell/home_shell_controller.dart';
import 'package:connectum/features/tickets/ticket_detail_controller.dart';
import 'package:connectum/features/workspace/workspace_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';
import '../tickets/ticket_fixtures.dart';

class _Submissions extends Fake implements SubmissionRepository {
  @override
  final submissions = <FormSubmission>[].obs;
  @override
  final definitions = <String, FormDefinition>{}.obs;
  @override
  final isLoaded = true.obs;
  @override
  final failures = <String, String>{}.obs;
  @override
  final drafts = <String, List<String>>{}.obs;
  @override
  final notice = RxnString();

  bool ownOk = true;
  int syncs = 0;

  @override
  Future<bool> syncFromServer() async {
    syncs++;
    return ownOk;
  }
}

class _Commands extends Fake implements CommandRepository {
  @override
  CommandSuggester createSuggester() =>
      CommandSuggester((input, page, reqId) async => null);
}

class _Connectivity extends FakeConnectivity {
  void set(AppConnectivity next) => state.value = next;
}

FormSubmission _own(int id, int ts, {String sync = 'synced'}) => FormSubmission(
  submissionId: sync == 'synced' ? '$id' : 'temp-$id',
  tstruct: 'help_ticket',
  byUser: 'ana',
  ts: ts,
  valuesJson: jsonEncode({'title': 'Mine $id'}),
  syncState: sync,
);

Map<String, dynamic> _row(int id, {String by = 'rhea', int ts = 100}) => {
  'id': id,
  'tstruct': 'help_ticket',
  'by': by,
  'holder': 'ana',
  'ts': ts,
  'values': {'title': 'Row $id', 'stage': 'Open'},
};

Map<String, dynamic> _page(List<Map<String, dynamic>> rows) => {
  'submissions': rows,
  'structures': {
    'help_ticket': {
      'caption': 'Ticket',
      'fields': {'title': 'Title', 'stage': 'Stage'},
      'status': {
        'field': 'stage',
        'statuses': ['Open', 'Done'],
        'final': ['Done'],
      },
    },
  },
  'total': rows.length,
  'hasMore': false,
  'next': null,
};

Future<void> _wait([int ms = 60]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late FakeStore store;
  late _Submissions submissions;
  late _Connectivity connectivity;
  late TicketRepository tickets;
  late WorkspaceRepository workspace;
  late WorkspaceController c;
  late _Messages messages;

  List<String> keys() => [
    for (final r in c.rows)
      if (r.card != null) r.key,
  ];

  Future<void> start({HomeShellController? shell}) async {
    workspace = WorkspaceRepository(
      socket,
      store,
      tickets,
      syncOwn: submissions.syncFromServer,
      debounce: const Duration(milliseconds: 10),
      minGap: Duration.zero,
      pageGap: Duration.zero,
    )..onInit();
    c = WorkspaceController(
      submissions: submissions,
      store: store,
      connectivity: connectivity,
      formOptions: _FormOptions(),
      shell: shell,
      commands: _Commands(),
      messages: messages,
      workspace: workspace,
      tickets: tickets,
      newTicketDetail: (id) => TicketDetailController(
        ticketId: id,
        tickets: tickets,
        files: FakeFiles(),
        connectivity: connectivity,
      ),
    )..onInit();
    await _wait();
  }

  setUp(() {
    messages = _Messages();
    socket = FakeSocket()..goOnline();
    store = FakeStore(user: 'ana');
    submissions = _Submissions();
    connectivity = _Connectivity();
    tickets = TicketRepository(socket, store, FakeConversations())..onInit();
    socket.answers[RecordCmd.mine] = (_) => _page(const []);
  });

  tearDown(() {
    c.onClose();
    workspace.onClose();
    tickets.onClose();
  });

  test('own and received records are one list, newest at the bottom, each '
      'record once', () async {
    submissions.submissions.assignAll([_own(5, 500), _own(6, 900)]);
    socket.answers[RecordCmd.mine] = (a) => a['as'] == 'involved'
        ? _page([_row(7, ts: 700), _row(6, by: 'ana', ts: 900)])
        : _page([_row(8, ts: 300), _row(7, ts: 700)]);
    await start();
    // rows are newest first (the list is reversed); keys: own c-, received rec-
    expect(keys(), ['c-6', 'rec-7', 'c-5', 'rec-8']);
    expect(c.viewState.value, AppViewState.content);
    expect(socket.count(RecordCmd.mine), 2);
  });

  test('only the latest 100 own records are cards; one still waiting to be '
      'sent always is', () async {
    submissions.submissions.assignAll([
      for (var i = 1; i <= 130; i++) _own(i, 1000 + i),
      _own(999, 1, sync: 'pending'),
    ]);
    await start();
    final own = keys().where((k) => k.startsWith('c-')).toList();
    expect(own, hasLength(WorkspaceController.ownCards + 1));
    expect(own, contains('c-temp-999'));
    expect(own, isNot(contains('c-1')));
    expect(own, contains('c-130'));
  });

  test('a received card opens the record; the menu reads record.actions '
      'only when it is opened', () async {
    socket.answers[RecordCmd.mine] = (a) =>
        a['as'] == 'with' ? _page([_row(8)]) : _page(const []);
    socket.answers[RecordCmd.actions] = fixtureData('record_actions');
    await start();
    final card = c.rows.firstWhere((r) => r.isReceived).card!;
    expect(c.recordIdOf(card), 8);
    expect(socket.count(RecordCmd.actions), 0);
    c.openRecordMenu(card);
    c.openRecordMenu(card);
    await _wait();
    expect(socket.count(RecordCmd.actions), 1);
    expect(tickets.stateOf(8)!.items, isNotEmpty);
  });

  group('stored notes', () {
    List<String> order() => [
      for (final r in c.rows)
        if (r.card != null || r.message != null) r.key,
    ];

    test('notes and cards are one list by time; a deleted note is not '
        'drawn', () async {
      submissions.submissions.assignAll([_own(5, 500), _own(6, 900)]);
      messages.notes.assignAll([
        _note('11', 700),
        _note('12', 100),
        _note('13', 800, isDeleted: true),
      ]);
      await start();
      expect(order(), ['c-6', 'm-11', 'c-5', 'm-12']);
    });

    test('a note that arrives later is added in place, no network '
        'needed', () async {
      connectivity.set(AppConnectivity.offline);
      socket.goOffline();
      messages.notes.assignAll([_note('11', 700)]);
      await start();
      expect(order(), ['m-11']);
      messages.notes.add(_note('12', 800));
      await _wait();
      expect(order(), ['m-12', 'm-11']);
      expect(c.viewState.value, AppViewState.content);
    });

    test('a note is never counted as a card', () async {
      messages.notes.assignAll([_note('11', 700)]);
      await start();
      expect(keys(), isEmpty);
    });
  });

  group('states', () {
    test('nothing yet and the read worked: the normal empty state, not an '
        'error', () async {
      await start();
      expect(c.viewState.value, AppViewState.content);
      expect(c.rows, isEmpty);
      expect(workspace.isLoaded.value, isTrue);
    });

    test('the read failed and there is nothing to show: an error with '
        'retry, never the empty state', () async {
      socket.answers[RecordCmd.mine] = const SocketCallError('timeout');
      await start();
      expect(c.viewState.value, AppViewState.error);
      socket.answers[RecordCmd.mine] = (_) => _page([_row(8)]);
      c.retry();
      expect(c.viewState.value, AppViewState.loading);
      await _wait();
      expect(c.viewState.value, AppViewState.content);
      expect(keys(), ['rec-8']);
    });

    test('a failure after a failure still leaves the loading state', () async {
      socket.answers[RecordCmd.mine] = const SocketCallError('timeout');
      await start();
      c.retry();
      await _wait();
      expect(c.viewState.value, AppViewState.error);
    });

    test(
      'the read failed but there are cards: they stay, with a notice',
      () async {
        submissions.submissions.assignAll([_own(5, 500)]);
        socket.answers[RecordCmd.mine] = const SocketCallError('timeout');
        await start();
        expect(c.viewState.value, AppViewState.content);
        expect(keys(), ['c-5']);
        expect(c.notice.value, contains("Couldn't refresh"));
      },
    );

    test('offline is never an error: the cache is shown', () async {
      connectivity.set(AppConnectivity.offline);
      socket.goOffline();
      await start();
      c.retry();
      await _wait();
      workspace.request(now: true);
      await _wait();
      expect(workspace.hasError.value, isTrue);
      connectivity.set(AppConnectivity.offline);
      await _wait();
      expect(c.viewState.value, isNot(AppViewState.error));
    });
  });

  test('the Approvals icon opens the Inbox with the approvals pane', () async {
    final shell = _Shell();
    await start(shell: shell);
    c.openApprovals();
    expect(shell.opened, [true]);
  });

  test('switching organisation takes the other organisation\'s received '
      'records off the screen', () async {
    socket.answers[RecordCmd.mine] = (a) =>
        a['as'] == 'with' ? _page([_row(8)]) : _page(const []);
    await start();
    expect(keys(), ['rec-8']);
    socket.answers[RecordCmd.mine] = (_) => _page(const []);
    store.switchTo('ana', org: 'other');
    expect(keys(), isEmpty);
    await _wait();
    expect(keys(), isEmpty);
    expect(workspace.isLoaded.value, isTrue);
  });
}

class _FormOptions extends Fake implements FormOptionsRepository {}

class _Messages extends Fake implements MessageRepository {
  final notes = <Message>[].obs;

  @override
  Future<RxList<Message>> openSelf() async => notes;
}

Message _note(String id, int ts, {bool isDeleted = false}) => Message(
  msgId: id,
  convId: 'self',
  sender: 'ana',
  isMine: true,
  text: 'note $id',
  ts: ts,
  status: MessageStatus.sent,
  isDeleted: isDeleted,
);

class _Shell extends Fake implements HomeShellController {
  final opened = <bool>[];

  @override
  void openInbox({bool approvals = false}) => opened.add(approvals);
}
