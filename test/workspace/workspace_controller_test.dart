import 'dart:convert';

import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/data/commands/command_reply.dart';
import 'package:connectum/data/models/form_definition.dart';
import 'package:connectum/data/models/form_submission.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/models/message_mark.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/command_repository.dart';
import 'package:connectum/data/repositories/form_options_repository.dart';
import 'package:connectum/data/repositories/marks_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/repositories/workspace_repository.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/home_shell/home_shell_controller.dart';
import 'package:connectum/features/tickets/ticket_detail_controller.dart';
import 'package:connectum/features/workspace/workspace_controller.dart';
import 'package:connectum/features/workspace/widgets/workspace_context_bar.dart';
import 'package:connectum/features/workspace/widgets/workspace_message.dart';
import 'package:connectum/features/workspace/widgets/workspace_selection.dart';
import 'package:connectum/features/workspace/widgets/workspace_pinned_bar.dart';
import 'package:connectum/features/workspace/widgets/workspace_saved_sheet.dart';
import 'package:flutter/material.dart';
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
  final ran = <String>[];

  @override
  CommandSuggester createSuggester() =>
      CommandSuggester((input, page, reqId) async => null);

  @override
  Future<HashResult> run(
    String line, {
    String? activeConvId,
    bool isConfirmed = false,
  }) async {
    ran.add(line);
    return const HashResult(HashKind.done, '');
  }
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
  late _Marks marks;
  late _Commands commands;

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
      commands: commands,
      messages: messages,
      marks: marks,
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
    marks = _Marks();
    commands = _Commands();
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

  group('the composer', () {
    Future<void> type(String value) async {
      c.text.text = value;
      await c.send();
      await _wait();
    }

    test('plain text becomes a note: queued as self, field cleared', () async {
      await start();
      await type('  remember the milk ');
      expect(messages.sentNotes, ['self|remember the milk']);
      expect(c.text.text, isEmpty);
      expect(c.nudge.value, isNull);
      expect(commands.ran, isEmpty);
    });

    test('a # line goes to the command runner and is not stored', () async {
      await start();
      await type('#help');
      expect(commands.ran, ['#help']);
      expect(messages.sentNotes, isEmpty);
    });

    test(
      'text over 2000 characters is refused with a message and kept',
      () async {
        await start();
        await type('a' * 2001);
        expect(messages.sentNotes, isEmpty);
        expect(c.nudge.value, WorkspaceController.tooLongText);
        expect(c.text.text, hasLength(2001));
      },
    );

    test('a refused note stays in the field with the reason', () async {
      await start();
      messages
        ..next = SendResult.blocked
        ..lastBlock = 'Your security key changed on another device';
      await type('hello');
      expect(c.nudge.value, 'Your security key changed on another device');
      expect(c.text.text, 'hello');
    });

    test('@name alone asks for a message; it is not a note', () async {
      await start();
      await type('@rhea');
      expect(c.nudge.value, 'Add a message after @rhea.');
      expect(messages.sentNotes, isEmpty);
    });

    test('pending and failed notes are rows; a tap retries', () async {
      await start();
      messages.notes.assignAll([
        _note('50', 100),
        Message(
          msgId: 'temp-1',
          convId: 'self',
          sender: 'ana',
          isMine: true,
          text: 'waiting',
          ts: 200,
          status: MessageStatus.pending,
        ),
        Message(
          msgId: 'temp-2',
          convId: 'self',
          sender: 'ana',
          isMine: true,
          text: 'broken',
          ts: 200,
          status: MessageStatus.failed,
        ),
      ]);
      await _wait();
      expect(
        [
          for (final r in c.rows)
            if (r.message != null) r.message!.msgId,
        ],
        ['temp-2', 'temp-1', '50'],
      );
      c.retryNote(messages.notes.last);
      await _wait();
      expect(messages.retried, ['temp-2']);
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

  group('edit, reply and delete a note', () {
    Message sentNote(String id, {String text = 'hello'}) => Message(
      msgId: id,
      convId: 'self',
      sender: 'ana',
      isMine: true,
      text: text,
      ts: DateTime.now().millisecondsSinceEpoch,
      status: MessageStatus.sent,
    );

    test(
      'Edit puts the text in the field; sending edits it and clears the mode',
      () async {
        await start();
        final m = sentNote('7', text: 'first');
        c.startEdit(m);
        expect(c.editing.value, m);
        expect(c.text.text, 'first');
        c.text.text = 'second';
        c.onChanged('second');
        await c.send();
        expect(messages.edits, ['7|second']);
        expect(messages.sentNotes, isEmpty);
        expect(c.editing.value, isNull);
        expect(c.text.text, isEmpty);
      },
    );

    test('cancelling an edit empties the field and sends nothing', () async {
      await start();
      c.startEdit(sentNote('7'));
      c.cancelEdit();
      expect(c.editing.value, isNull);
      expect(c.text.text, isEmpty);
      expect(messages.edits, isEmpty);
    });

    test('an edit past the window does not start', () async {
      await start();
      messages.isEditable = false;
      c.startEdit(sentNote('7'));
      expect(c.editing.value, isNull);
    });

    test(
      'Reply sends the note with the quoted id and clears the bar',
      () async {
        await start();
        c.startReply(sentNote('9'));
        expect(c.replying.value?.msgId, '9');
        c.text.text = 'answer';
        c.onChanged('answer');
        await c.send();
        expect(messages.sentNotes, ['self|answer']);
        expect(messages.lastReplyTo, '9');
        expect(c.replying.value, isNull);
      },
    );

    test('a refused reply keeps the text and drops the bar', () async {
      await start();
      messages.next = SendResult.invalid;
      c.startReply(sentNote('9'));
      c.text.text = 'answer';
      c.onChanged('answer');
      await c.send();
      expect(c.text.text, 'answer');
      expect(c.replying.value, isNull);
      expect(c.nudge.value, isNotNull);
    });

    test('Delete goes to the repository', () async {
      await start();
      await c.deleteNote(sentNote('4'));
      expect(messages.deleted, ['4']);
    });

    test('only a sent note of mine can be deleted from the menu', () async {
      await start();
      final pending = Message(
        msgId: 'temp-1',
        convId: 'self',
        sender: 'ana',
        isMine: true,
        text: 'x',
        ts: 1,
        status: MessageStatus.pending,
      );
      expect(c.canDeleteNote(sentNote('4')), isTrue);
      expect(c.canDeleteNote(pending), isFalse);
    });
  });

  test('a note older than what is loaded says so', () async {
    await start();
    await c.openNote('999');
    expect(c.notice.value, WorkspaceController.olderNoteText);
  });

  group('the note menu and the bars at 320 px, text scale 1.5', () {
    Message sentNote(String id) => Message(
      msgId: id,
      convId: 'self',
      sender: 'ana',
      isMine: true,
      text:
          'A rather long note that would not fit on one line at this size, '
          'to prove the bar cuts it with an ellipsis',
      ts: DateTime.now().millisecondsSinceEpoch,
      status: MessageStatus.sent,
    );

    Future<void> pump(WidgetTester t, Widget child) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      );
      await t.pump();
    }

    Future<void> select(
      WidgetTester t,
      List<Message> list,
      List<String> ids,
    ) async {
      messages.notes.assignAll(list);
      await t.runAsync(_wait);
      for (final id in ids) {
        c.selection.onTap(id);
      }
      await pump(t, WorkspaceSelectionBar(controller: c));
    }

    Future<void> openMore(WidgetTester t) async {
      await t.tap(find.byTooltip('More'));
      await t.pumpAndSettle();
    }

    testWidgets(
      'a sent note: Reply, Save, Delete as icons; Copy, Pin, Edit in More; '
      'no reactions, no forward',
      (t) async {
        await t.runAsync(start);
        await select(t, [sentNote('7')], ['7']);
        for (final label in ['Reply', 'Save', 'Delete']) {
          expect(find.byTooltip(label), findsOneWidget);
        }
        expect(find.byTooltip('Forward'), findsNothing);
        expect(find.byTooltip('Retry'), findsNothing);
        await openMore(t);
        for (final label in ['Copy', 'Pin', 'Edit']) {
          expect(find.text(label), findsOneWidget);
        }
        await t.tap(find.text('Pin'));
        await t.pumpAndSettle();
        expect(marks.calls, ['pin|7']);
        expect(c.selection.isActive, isFalse);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('Save on the icon saves the note and leaves selection', (
      t,
    ) async {
      await t.runAsync(start);
      await select(t, [sentNote('7')], ['7']);
      await t.tap(find.byTooltip('Save'));
      await t.pump();
      expect(marks.calls, ['save|7']);
      expect(c.selection.isActive, isFalse);
    });

    testWidgets('a saved and pinned note offers the way back', (t) async {
      await t.runAsync(start);
      marks.mark('7', isSaved: true, isPinned: true);
      await select(t, [sentNote('7')], ['7']);
      expect(find.byTooltip('Remove from saved'), findsOneWidget);
      expect(find.byTooltip('Save'), findsNothing);
      await openMore(t);
      expect(find.text('Unpin'), findsOneWidget);
      expect(find.text('Pin'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      'two notes: no Reply, Pin or Edit; Save, Delete and Copy stay',
      (t) async {
        await t.runAsync(start);
        await select(t, [sentNote('7'), sentNote('8')], ['7', '8']);
        expect(find.text('2'), findsOneWidget);
        expect(find.byTooltip('Reply'), findsNothing);
        expect(find.byTooltip('Save'), findsOneWidget);
        expect(find.byTooltip('Delete'), findsOneWidget);
        await openMore(t);
        expect(find.text('Copy'), findsOneWidget);
        expect(find.text('Pin'), findsNothing);
        expect(find.text('Edit'), findsNothing);
      },
    );

    testWidgets('a note with no server id cannot be saved or pinned', (
      t,
    ) async {
      await t.runAsync(start);
      final local = Message(
        msgId: 'temp-9',
        convId: 'self',
        sender: 'ana',
        isMine: true,
        text: 'x',
        ts: 1,
        status: MessageStatus.pending,
      );
      expect(c.canMarkNote(local), isFalse);
      expect(c.canMarkNote(sentNote('7')), isTrue);
    });

    testWidgets('the pinned bar shows the newest pin, a count and unpins', (
      t,
    ) async {
      await t.runAsync(start);
      messages.notes.assignAll([_note('7', 100), _note('8', 200)]);
      marks.mark('7', isPinned: true, ts: 10);
      marks.mark('8', isPinned: true, ts: 20);
      await pump(t, WorkspacePinnedBar(controller: c));
      expect(find.text('note 8'), findsOneWidget);
      expect(find.text('2 pinned'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('pinned-count')));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('note 7'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('pinned-unpin')));
      expect(marks.calls, ['unpin|8']);
      expect(t.takeException(), isNull);
    });

    testWidgets('the saved and pinned markers sit beside the time', (t) async {
      await t.runAsync(start);
      await pump(
        t,
        Column(
          children: [
            WorkspaceMessage(
              message: sentNote('7'),
              original: null,
              me: 'ana',
              isSaved: true,
              isPinned: true,
            ),
            WorkspaceMessage(message: sentNote('8'), original: null, me: 'ana'),
          ],
        ),
      );
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('no pins: nothing is drawn', (t) async {
      await t.runAsync(start);
      await pump(t, WorkspacePinnedBar(controller: c));
      expect(find.byKey(const ValueKey('pinned-bar')), findsNothing);
    });

    testWidgets('a pin of a note not loaded shows the server words', (t) async {
      await t.runAsync(start);
      marks.mark('50', isPinned: true, preview: 'from the server');
      marks.mark('51', isPinned: true, ts: 0);
      await pump(t, WorkspacePinnedBar(controller: c));
      expect(c.pinLines().map((l) => l.text), [
        'from the server',
        'Encrypted note',
      ]);
    });

    testWidgets('the saved list: saved notes, newest first, jump or remove', (
      t,
    ) async {
      await t.runAsync(start);
      messages.notes.assignAll([
        _note('7', 100),
        _note('8', 200),
        _note('9', 300),
      ]);
      marks.mark('7', isSaved: true);
      marks.mark('9', isSaved: true);
      await pump(t, WorkspaceSavedSheet(controller: c));
      expect(find.text('note 9'), findsOneWidget);
      expect(find.text('note 7'), findsOneWidget);
      expect(find.text('note 8'), findsNothing);
      expect(
        t.getTopLeft(find.text('note 9')).dy <
            t.getTopLeft(find.text('note 7')).dy,
        isTrue,
      );
      await t.tap(find.byIcon(Icons.bookmark_remove_outlined).first);
      expect(marks.calls, ['save|9']);
      expect(t.takeException(), isNull);
    });

    testWidgets('the saved list with nothing saved says so', (t) async {
      await t.runAsync(start);
      await pump(t, WorkspaceSavedSheet(controller: c));
      expect(find.textContaining('No saved notes yet'), findsOneWidget);
    });

    testWidgets('when it cannot be edited Edit is hidden, Delete stays', (
      t,
    ) async {
      await t.runAsync(start);
      messages.isEditable = false;
      await select(t, [sentNote('7')], ['7']);
      expect(find.byTooltip('Delete'), findsOneWidget);
      await openMore(t);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets(
      'a note that was not sent keeps retry and remove, nothing else',
      (t) async {
        await t.runAsync(start);
        final failed = Message(
          msgId: 'temp-5',
          convId: 'self',
          sender: 'ana',
          isMine: true,
          text: 'x',
          ts: 1,
          status: MessageStatus.failed,
        );
        await select(t, [failed], ['temp-5']);
        expect(find.byTooltip('Retry'), findsOneWidget);
        expect(find.byTooltip('Remove'), findsOneWidget);
        expect(find.byTooltip('Reply'), findsNothing);
        expect(find.byTooltip('Save'), findsNothing);
        expect(find.byTooltip('More'), findsNothing);
        await t.tap(find.byTooltip('Remove'));
        await t.pump();
        expect(messages.deleted, ['temp-5']);
        expect(c.selection.isActive, isFalse);
      },
    );

    testWidgets('the edit bar and the reply bar do not overflow', (t) async {
      await t.runAsync(start);
      await pump(
        t,
        Column(
          children: [
            WorkspaceContextBar(
              message: sentNote('1'),
              label: 'Editing note',
              cancelLabel: 'Cancel edit',
              onCancel: () {},
            ),
            WorkspaceContextBar(
              message: sentNote('2'),
              label: 'Replying to note',
              cancelLabel: 'Cancel reply',
              onCancel: () {},
            ),
          ],
        ),
      );
      expect(find.text('Editing note'), findsOneWidget);
      expect(find.text('Replying to note'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}

class _FormOptions extends Fake implements FormOptionsRepository {}

class _Marks extends Fake implements MarksRepository {
  @override
  final marks = <String, MessageMark>{}.obs;
  @override
  final pinned = <MessageMark>[].obs;
  final calls = <String>[];

  @override
  Stream<String> get notices => const Stream.empty();

  @override
  Future<void> open() async {}

  @override
  bool isSaved(String msgId) => marks[msgId]?.isSaved ?? false;

  @override
  bool isPinned(String msgId) => marks[msgId]?.isPinned ?? false;

  @override
  Future<void> toggleSave(String msgId) async => calls.add('save|$msgId');

  @override
  Future<void> togglePin(String msgId) async => calls.add('pin|$msgId');

  @override
  Future<void> unpin(String msgId) async => calls.add('unpin|$msgId');

  void mark(
    String id, {
    bool isSaved = false,
    bool isPinned = false,
    int ts = 1,
    String preview = '',
  }) {
    marks[id] = MessageMark(
      convId: 'self',
      msgId: id,
      isConfirmedSaved: isSaved,
      isConfirmedPinned: isPinned,
      pinnedTs: ts,
      preview: preview,
    );
    pinned.assignAll(
      [
        for (final m in marks.values)
          if (m.isPinned) m,
      ]..sort((a, b) => b.pinnedTs.compareTo(a.pinnedTs)),
    );
  }
}

class _Messages extends Fake implements MessageRepository {
  final notes = <Message>[].obs;
  final sentNotes = <String>[];
  final retried = <String>[];
  SendResult next = SendResult.queued;
  final edits = <String>[];
  String? lastReplyTo;
  final deleted = <String>[];
  bool isEditable = true;

  @override
  Stream<String> get notices => const Stream.empty();

  @override
  bool canEditNote(Message m) => isEditable && m.status == MessageStatus.sent;

  @override
  bool canReplyToNote(Message m) => m.status == MessageStatus.sent;

  @override
  Future<bool> editText(String msgId, String text) async {
    edits.add('$msgId|$text');
    return true;
  }

  @override
  Future<DeleteResult> deleteMessage(Message m) async {
    deleted.add(m.msgId);
    return DeleteResult.deleted;
  }

  @override
  String lastBlock = '';

  @override
  Future<SendResult> sendText(
    String convId,
    String text, {
    String? replyTo,
  }) async {
    if (next == SendResult.queued) sentNotes.add('$convId|$text');
    lastReplyTo = replyTo;
    return next;
  }

  @override
  Future<void> retry(String msgId) async => retried.add(msgId);

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
  void openInbox({
    bool approvals = false,
    int? recordId,
    bool isList = false,
  }) => opened.add(approvals);
}
