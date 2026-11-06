import 'package:connectum/data/db/app_database.dart';
import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/data/models/thread_names.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/chats/chats_controller.dart';
import 'package:connectum/features/chats/record_rename_controller.dart';
import 'package:connectum/features/chats/widgets/conversation_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';

// The replies below are built from the web (ConnectumChatScreen.jsx:329-337,
// :942) and the server (sd_cmds_people.erl, sd_cmds_forms.erl:341-352,
// sd_recthread.erl:164-196) with the SD_ACTIONS_REFERENCE description; neither
// the Postman collection nor reference/ has a sample reply for these calls.

const _recordNames = {
  'names': {'rec-ticket-12': 'Ticket #12: printer is down'},
  'canRename': ['rec-ticket-12'],
  'hidden': ['rec-claim-3'],
};

Map<String, Object?> _row(String conv, {String? thread, String? title}) => {
  'conv_id': conv,
  'kind': conv.split(':').first,
  'title': title ?? conv.split(':').last,
  'thread_title': thread,
};

Conversation _conv(String id, {String? title, bool canRename = false}) =>
    Conversation(
      convId: id,
      kind: 'group',
      title: title ?? 'Ticket #12',
      canRename: canRename,
    );

class _Db extends Fake implements AppDatabase {
  final updates = <List<Object?>>[];

  @override
  Future<int> update(String sql, [List<Object?> args = const []]) async {
    updates.add(args);
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> args = const [],
  ]) async => [];
}

class _Chats extends Fake implements ChatsController {
  @override
  bool get isOffline => false;
}

void main() {
  group('parsing', () {
    test('record.names: titles, canRename and hidden', () {
      final r = RecordNames.fromReply(_recordNames);
      expect(r.names, {'rec-ticket-12': 'Ticket #12: printer is down'});
      expect(r.canRename, {'rec-ticket-12'});
      expect(r.hidden, {'rec-claim-3'});
    });
    test('record.names: missing or odd fields give empty sets', () {
      final r = RecordNames.fromReply({'names': null, 'canRename': 'x'});
      expect(r.names, isEmpty);
      expect(r.canRename, isEmpty);
      expect(r.hidden, isEmpty);
    });
    test('care.names: lower-case usernames, empty names dropped', () {
      final n = CareNames.fromReply({
        'names': {'Ana.Lopez': 'Ana Lopez', 'bob': ''},
      });
      expect(n, {'ana.lopez': 'Ana Lopez'});
    });
    test('org.name: the name, trimmed; empty when missing', () {
      expect(CareNames.orgFromReply({'name': ' Acme Co '}), 'Acme Co');
      expect(CareNames.orgFromReply({}), '');
    });
    test('record.rename: id and title', () {
      final r = RecordRename.fromReply({
        'id': 12,
        'title': 'Printer on floor 2',
      });
      expect(r.id, 12);
      expect(r.title, 'Printer on floor 2');
    });
    test('name check: 60 characters pass, 61 are refused, empty passes', () {
      expect(RecordRename.problemWith('a' * 60), isNull);
      expect(RecordRename.problemWith('a' * 61), RecordRename.tooLong);
      expect(RecordRename.problemWith('   '), isNull);
    });
  });

  group('the title of a row', () {
    test('the server title (renamed or made) beats the tidied name', () {
      final c = Conversation.fromRow(
        _row('group:rec-ticket-12', thread: 'Printer on floor 2'),
      );
      expect(c.title, 'Printer on floor 2');
    });
    test('a care or organisation name beats the tidied username', () {
      final c = Conversation.fromRow(
        _row('group:care-ana.lopez', thread: 'Acme Co'),
      );
      expect(c.title, 'Acme Co');
    });
    test('until a name arrives the tidied name shows', () {
      expect(
        Conversation.fromRow(_row('group:care-ana.lopez')).title,
        'Ana Lopez',
      );
      expect(
        Conversation.fromRow(_row('group:rec-ticket-12')).title,
        'Ticket #12',
      );
    });
    test('a plain group keeps its own name', () {
      expect(Conversation.fromRow(_row('group:sales')).title, 'sales');
    });
    test('canRename comes from the stored flag', () {
      final r = _row('group:rec-ticket-12')..['can_rename'] = 1;
      expect(Conversation.fromRow(r).canRename, isTrue);
      expect(
        Conversation.fromRow(_row('group:rec-ticket-12')).canRename,
        isFalse,
      );
    });
  });

  group('the row menu', () {
    Future<void> open(WidgetTester t, Conversation c) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationActionsSheet(conversation: c, controller: _Chats()),
        ),
      ),
    );

    testWidgets('shows Rename when canRename is true', (t) async {
      await open(t, _conv('group:rec-ticket-12', canRename: true));
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Pin'), findsOneWidget);
    });
    testWidgets('hides Rename when canRename is false', (t) async {
      await open(t, _conv('group:rec-ticket-12'));
      expect(find.text('Rename'), findsNothing);
      expect(find.text('Pin'), findsOneWidget);
    });
  });

  group('rename a record conversation', () {
    late FakeSocket socket;
    late _Db db;
    late ConversationRepository repo;

    setUp(() {
      socket = FakeSocket()..goOnline();
      db = _Db();
      repo = ConversationRepository(db, FakeStore(), socket, FakeE2e());
    });

    test('shows the new title at once and keeps the reply title', () async {
      final c = _conv('group:rec-ticket-12', canRename: true);
      repo.conversations.assignAll([c]);
      socket.answers['record.rename'] = {'id': 12, 'title': 'Printer, floor 2'};
      final done = repo.renameRecord(c, '  Printer, floor 2 ');
      expect(repo.conversations.single.title, 'Printer, floor 2');
      await done;
      expect(socket.calls.single.action, 'record.rename');
      expect(socket.calls.single.args, {'id': 12, 'name': 'Printer, floor 2'});
      expect(db.updates.single.first, 'Printer, floor 2');
    });

    test(
      'an empty name sends an empty name and shows the tidied one',
      () async {
        final c = _conv('group:rec-ticket-12', title: 'Custom');
        repo.conversations.assignAll([c]);
        socket.answers['record.rename'] = {
          'id': 12,
          'title': 'Ticket #12: printer is down',
        };
        final done = repo.renameRecord(c, '');
        expect(repo.conversations.single.title, 'Ticket #12');
        await done;
        expect(socket.calls.single.args, {'id': 12, 'name': ''});
        expect(db.updates.single.first, 'Ticket #12: printer is down');
      },
    );

    test('an error puts the old title back and rethrows', () async {
      final c = _conv('group:rec-ticket-12', title: 'Old name');
      repo.conversations.assignAll([c]);
      socket.answers['record.rename'] = const SocketCallError(
        'forbidden',
        'Only the person who saved the record can rename its conversation.',
      );
      final done = repo.renameRecord(c, 'New name');
      expect(repo.conversations.single.title, 'New name');
      await expectLater(done, throwsA(isA<SocketCallError>()));
      expect(repo.conversations.single.title, 'Old name');
      expect(db.updates, isEmpty);
    });

    test(
      'the sheet controller tells the server text and does not close',
      () async {
        final c = _conv('group:rec-ticket-12', title: 'Old name');
        repo.conversations.assignAll([c]);
        socket.answers['record.rename'] = const SocketCallError(
          'forbidden',
          'Only the person who saved the record can rename its conversation.',
        );
        final rename = RecordRenameController(
          onRename: (n) => repo.renameRecord(c, n),
          isOffline: () => false,
        );
        expect(await rename.save('New name'), isFalse);
        expect(
          rename.lastNotice,
          'Only the person who saved the record can rename its conversation.',
        );
        expect(repo.conversations.single.title, 'Old name');
        expect(rename.isSaving.value, isFalse);
      },
    );

    test('a name over 60 characters is refused before sending', () async {
      final rename = RecordRenameController(
        onRename: (n) async => fail('should not send'),
        isOffline: () => false,
      );
      expect(await rename.save('a' * 61), isFalse);
      expect(rename.error.value, RecordRename.tooLong);
      expect(socket.calls, isEmpty);
    });

    test('offline: nothing is sent, the person is told', () async {
      final rename = RecordRenameController(
        onRename: (n) async => fail('should not send'),
        isOffline: () => true,
      );
      expect(await rename.save('Fine'), isFalse);
      expect(rename.lastNotice, RecordRenameController.needsConnection);
    });
  });
}
