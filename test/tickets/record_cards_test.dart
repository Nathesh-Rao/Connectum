import 'dart:convert';
import 'dart:io';

import 'package:connectum/data/models/form_card.dart';
import 'package:connectum/data/models/form_entry.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/tickets/models/record_card_rule.dart';
import 'package:connectum/features/tickets/models/record_history_card.dart';
import 'package:connectum/features/tickets/ticket_detail_controller.dart';
import 'package:connectum/features/tickets/models/card_menu.dart';
import 'package:connectum/features/tickets/widgets/record_menu_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import 'ticket_fixtures.dart';

FormCardData _card({
  String id = '24',
  String structure = 'help_ticket',
  bool isReadOnly = false,
  bool hasResult = false,
  List<FormEntry> entries = const [],
}) => FormCardData(
  id: id,
  caption: 'Card',
  structure: structure,
  scope: '',
  by: 'ben',
  ts: 1,
  entries: entries,
  isReadOnly: isReadOnly,
  hasResult: hasResult,
);

FormCardData? _fromForm(Map<String, dynamic> form) => FormCardData.fromMessage(
  Message(
    msgId: '1',
    convId: 'dm:ben',
    sender: 'ben',
    isMine: false,
    text: 'Form',
    ts: 1,
    status: MessageStatus.read,
    kind: 'form',
    formJson: jsonEncode(form),
  ),
);

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the card rule (the web\'s: numeric submissionId, not read-only, '
      'not a data-source result)', () {
    test('truth table', () {
      final cases = <String, (FormCardData, int?)>{
        'ordinary form card': (_card(), 24),
        'a form without a status is a record card too': (
          _card(structure: 'leave_request'),
          24,
        ),
        'still waiting to be sent (temp id)': (_card(id: 'temp-1700'), null),
        'record history card (read-only)': (
          _card(id: '9001', structure: 'record_history', isReadOnly: true),
          null,
        ),
        'record history card without the flag': (
          _card(id: '9001', structure: 'record_history'),
          null,
        ),
        'any other read-only card': (_card(isReadOnly: true), null),
        'a data-source result': (_card(hasResult: true), null),
        'no numeric id': (_card(id: 'abc'), null),
        'an empty id': (_card(id: ''), null),
      };
      for (final e in cases.entries) {
        expect(RecordCardRule.of(e.value.$1).id, e.value.$2, reason: e.key);
      }
    });

    test('every answer has a reason for the decision line', () {
      expect(RecordCardRule.of(_card()).rule, RecordCardRule.recordRule);
      expect(
        RecordCardRule.of(_card(hasResult: true)).rule,
        contains('result'),
      );
      expect(
        RecordCardRule.of(_card(id: '9', structure: 'record_history')).rule,
        contains('record_history'),
      );
    });

    test('read from the message: submissionId, readonly and result', () {
      final base = {
        'structure': 'help_ticket',
        'caption': 'Help ticket',
        'submissionId': 24,
        'by': 'ben',
        'fields': const [],
      };
      expect(RecordCardRule.of(_fromForm(base)!).id, 24);
      // The old flag changes nothing either way.
      expect(RecordCardRule.of(_fromForm({...base, 'ticket': true})!).id, 24);
      expect(RecordCardRule.of(_fromForm({...base, 'ticket': false})!).id, 24);
      expect(
        RecordCardRule.of(_fromForm({...base, 'readonly': true})!).id,
        isNull,
      );
      expect(
        RecordCardRule.of(
          _fromForm({
            ...base,
            'result': {'rows': 3},
          })!,
        ).id,
        isNull,
      );
      expect(RecordCardRule.of(_fromForm({...base})!).isRecord, isTrue);
    });

    test('a history card opens the record in its own Record field, not its '
        'submissionId', () {
      final c = _card(
        id: '9001',
        structure: 'record_history',
        isReadOnly: true,
        entries: const [
          FormEntry(name: 'record', caption: 'Record', text: '24'),
        ],
      );
      expect(RecordCardRule.of(c).id, isNull);
      expect(RecordHistoryCard.recordIdOf(c), 24);
    });
  });

  group('record.actions is read lazily', () {
    late FakeSocket socket;
    late FakeStore store;
    late TicketRepository repo;

    setUp(() {
      socket = FakeSocket()..goOnline();
      store = FakeStore(user: 'ana');
      repo = TicketRepository(socket, store, FakeConversations())..onInit();
      socket.answers[RecordCmd.actions] = fixtureData('record_actions');
    });

    tearDown(() => repo.onClose());

    test('drawing cards, loading history and reading a list call nothing', () {
      for (var i = 1; i <= 50; i++) {
        final d = _card(id: '$i');
        expect(RecordCardRule.of(d).isRecord, isTrue);
        expect(repo.stateOf(i), isNull);
      }
      expect(socket.calls, isEmpty);
      expect(repo.cardReads, 0);
    });

    test('opening the menu is one record.actions, and nothing else', () async {
      await repo.ensureMenu(24);
      expect(socket.calls.map((c) => c.action), [RecordCmd.actions]);
      expect(socket.calls.single.args, {'id': 24});
      expect(repo.stateOf(24)!.items.map((i) => i.id), ['send', 'status']);
    });

    test(
      'two opens at once and a second open within 60 s are one read',
      () async {
        await Future.wait([repo.ensureMenu(24), repo.ensureMenu(24)]);
        await repo.ensureMenu(24);
        expect(socket.count(RecordCmd.actions), 1);
        expect(repo.cardReads, 1);
      },
    );

    test('another record is another read', () async {
      await repo.ensureMenu(24);
      await repo.ensureMenu(25);
      expect(socket.count(RecordCmd.actions), 2);
    });

    test('a record event invalidates: the menu is gone and a new open reads '
        'again', () async {
      await repo.ensureMenu(24);
      repo.onEvent({'type': 'sd_event', 'event': RecordEvents.changed});
      await Future<void>.delayed(
        TicketRepository.burst + const Duration(milliseconds: 50),
      );
      expect(repo.stateOf(24), isNull);
      await repo.ensureMenu(24);
      expect(socket.count(RecordCmd.actions), 2);
    });

    test('a refused read is kept for the 60 s too: no retry loop', () async {
      socket.answers[RecordCmd.actions] = const SocketCallError(
        'not_found',
        'No such record.',
      );
      await repo.ensureMenu(24);
      await repo.ensureMenu(24);
      await repo.ensureMenu(24);
      expect(socket.count(RecordCmd.actions), 1);
      expect(repo.stateOf(24), isNull);
    });

    test('the menu read never asks submission.get or the history', () async {
      await repo.ensureMenu(24);
      expect(socket.count(RecordCmd.get), 0);
      expect(socket.count(RecordCmd.history), 0);
    });
  });

  group('the two known BE gaps', () {
    late FakeSocket socket;
    late TicketRepository repo;
    late TicketDetailController c;

    final submission = {
      'submission': {
        'id': 24,
        'tstruct': 'help_ticket',
        'by': 'rhea',
        'holder': 'ben',
        'values': {'title': 'Printer', 'stage': 'Open'},
      },
    };

    setUp(() {
      socket = FakeSocket()..goOnline();
      repo = TicketRepository(
        socket,
        FakeStore(user: 'ana'),
        FakeConversations(),
      )..onInit();
    });

    tearDown(() {
      c.onClose();
      repo.onClose();
    });

    TicketDetailController open() => c = TicketDetailController(
      ticketId: 24,
      tickets: repo,
      files: FakeFiles(),
      connectivity: FakeConnectivity(),
    )..onInit();

    test('(a) record.actions not_found but submission.get ok: opens '
        'read-only, with the history, no actions, no error', () async {
      socket.answers[RecordCmd.get] = submission;
      socket.answers[RecordCmd.actions] = const SocketCallError(
        'not_found',
        'No such record.',
      );
      socket.answers[RecordCmd.history] = fixtureData('submission_history');
      open();
      await _settle();
      expect(c.viewState.value.name, 'content');
      expect(c.isGone.value, isFalse);
      expect(c.isReadOnly.value, isTrue);
      expect(c.isUnopenable.value, isFalse);
      expect(c.items, isEmpty);
      expect(c.ticket.value!.id, 24);
      expect(c.history.value!.events, isNotEmpty);
    });

    test('(a) is told by the repository, not thrown', () async {
      socket.answers[RecordCmd.get] = submission;
      socket.answers[RecordCmd.actions] = const SocketCallError('not_found');
      final detail = await repo.get(24);
      expect(detail.isReadOnly, isTrue);
      expect(detail.state.items, isEmpty);
    });

    test('(a) only not_found is the gap: another error still throws', () async {
      socket.answers[RecordCmd.get] = submission;
      socket.answers[RecordCmd.actions] = const SocketCallError('timeout');
      expect(repo.get(24), throwsA(isA<SocketCallError>()));
    });

    test('both not_found is a record that is gone', () async {
      socket.answers[RecordCmd.get] = const SocketCallError('not_found');
      socket.answers[RecordCmd.actions] = const SocketCallError('not_found');
      socket.answers[RecordCmd.history] = const SocketCallError('not_found');
      open();
      await _settle();
      expect(c.isGone.value, isTrue);
    });

    test('(b) listed but submission.get not_found: the list row, the '
        'notice, no history, no retry loop', () async {
      socket.answers[RecordCmd.mine] = {
        'submissions': [
          {
            'id': 24,
            'tstruct': 'help_ticket',
            'by': 'rhea',
            'holder': 'ben',
            'ts': 5,
            'values': {'title': 'Printer', 'stage': 'Open'},
          },
        ],
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
        'total': 1,
        'hasMore': false,
        'next': null,
      };
      await repo.mine(as: 'with');
      socket.answers[RecordCmd.get] = const SocketCallError('not_found');
      socket.answers[RecordCmd.actions] = fixtureData('record_actions');
      socket.answers[RecordCmd.history] = const SocketCallError('not_found');
      open();
      await _settle();
      expect(c.isGone.value, isFalse);
      expect(c.viewState.value.name, 'content');
      expect(c.isUnopenable.value, isTrue);
      expect(c.ticket.value!.values['title'], 'Printer');
      expect(c.history.value, isNull);
      // A refresh reads again but does not ask the refused submission.get
      // again inside the cache window.
      final gets = socket.count(RecordCmd.get);
      await c.reload();
      await c.reload();
      expect(socket.count(RecordCmd.get), gets);
    });

    test('(b) needs the list row: an id never listed is simply gone', () async {
      socket.answers[RecordCmd.get] = const SocketCallError('not_found');
      socket.answers[RecordCmd.actions] = const SocketCallError('not_found');
      socket.answers[RecordCmd.history] = const SocketCallError('not_found');
      open();
      await _settle();
      expect(c.isGone.value, isTrue);
      expect(c.isUnopenable.value, isFalse);
    });
  });

  group('drawing a card never reads the server', () {
    test('no view or widget of a card calls the repository', () {
      for (final path in const [
        'lib/features/conversation/conversation_view.dart',
        'lib/features/tickets/widgets/record_card_actions.dart',
        'lib/features/workspace/workspace_view.dart',
      ]) {
        final text = File(path).readAsStringSync();
        expect(text, isNot(contains('ensure')), reason: path);
        expect(text, isNot(contains('.get(')), reason: path);
      }
    });

    test('the old ticket flag and the old rules are gone', () {
      for (final path in const [
        'lib/data/models/form_card.dart',
        'lib/features/conversation/conversation_controller.dart',
        'lib/data/repositories/ticket_repository.dart',
      ]) {
        final text = File(path).readAsStringSync();
        expect(text, isNot(contains("['ticket']")), reason: path);
        expect(text, isNot(contains('isRecordForm')), reason: path);
        expect(text, isNot(contains('legacy ticket flag')), reason: path);
      }
    });

    testWidgets('the menu rows read nothing until the menu is opened', (
      tester,
    ) async {
      final socket = FakeSocket()..goOnline();
      final repo = TicketRepository(
        socket,
        FakeStore(user: 'ana'),
        FakeConversations(),
      )..onInit();
      addTearDown(repo.onClose);
      socket.answers[RecordCmd.actions] = fixtureData('record_actions');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordMenuRows(
              tickets: repo,
              recordId: 24,
              itemsFor: (state) => CardMenu.build(record: state),
              onPick: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(socket.calls, isEmpty);
      expect(find.text('Send'), findsNothing);
      final read = repo.ensureMenu(24);
      await tester.pump();
      await read;
      await tester.pump();
      expect(socket.count(RecordCmd.actions), 1);
      expect(find.text('Send'), findsOneWidget);
      expect(find.text('Update status'), findsOneWidget);
    });

    testWidgets('a record with no actions says so once the read is over', (
      tester,
    ) async {
      final socket = FakeSocket()..goOnline();
      final repo = TicketRepository(
        socket,
        FakeStore(user: 'ana'),
        FakeConversations(),
      )..onInit();
      addTearDown(repo.onClose);
      socket.answers[RecordCmd.actions] = const SocketCallError('not_found');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordMenuRows(
              tickets: repo,
              recordId: 24,
              itemsFor: (state) => CardMenu.build(record: state),
              onPick: (_) {},
            ),
          ),
        ),
      );
      await repo.ensureMenu(24);
      await tester.pump();
      expect(find.text('No actions available.'), findsOneWidget);
    });
  });
}
