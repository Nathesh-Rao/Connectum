import 'dart:async';

import 'package:connectum/data/db/app_database.dart';
import 'package:connectum/data/e2e/e2e_crypto.dart';
import 'package:connectum/data/e2e/e2e_key_store.dart';
import 'package:connectum/data/e2e/e2e_models.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/models/outbox_entry.dart';
import 'package:connectum/data/models/self_conversation.dart';
import 'package:connectum/data/models/session_info.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/e2e_repository.dart';
import 'package:connectum/data/repositories/encryption_policy.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Session extends Fake implements SessionStore {
  @override
  final current = Rxn<SessionInfo>();
  @override
  String? get orgId => 'org';
  @override
  String? get userId => 'Ann';
  @override
  bool get hasSession => true;
}

/// Records every command; answers a `/history` line from [history].
class _Socket extends Fake implements SocketService {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <String>[];
  final history = <String, Map<String, dynamic>>{};

  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  bool isCurrent(Map<String, dynamic> event) => true;
  @override
  final connection = SocketState.online.obs;
  @override
  bool get isOnline => connection.value == SocketState.online;
  @override
  StreamSubscription<void> listenOnline(
    String name,
    FutureOr<void> Function() run,
  ) => const Stream<void>.empty().listen((_) {});

  @override
  Future<bool> sendCommand(String line) async {
    if (!isOnline) return false;
    sent.add(line);
    final answer = history[line];
    if (answer != null) {
      scheduleMicrotask(() => controller.add({'type': 'history', ...answer}));
    }
    return true;
  }
}

class _E2e extends Fake implements E2eRepository {
  E2eReading reading = const E2eReading.pending();

  @override
  Stream<void> get unlockRequests => const Stream.empty();
  @override
  Stream<void> get registrations => const Stream.empty();
  @override
  Future<E2eReading> open({
    required String text,
    required String convId,
    String? expectConv,
    E2eDeviceKeys? keys,
    Future<String?> Function(String user, String deviceId)? signKeyFor,
    Future<E2eDevicePublic?> Function(String user, String deviceId)? deviceFor,
    Map<String, ({String ecdh, String sign})>? testPins,
  }) async => reading;
}

class _Conversations extends Fake implements ConversationRepository {
  @override
  Stream<String> get receiptsChanged => const Stream.empty();
  @override
  Future<void> reload() async {}
  @override
  Future<void> requestLists() async {}
  @override
  Future<void> noteDelivered(String convId, String id) async {}
}

class _Policy extends Fake implements EncryptionPolicy {}

Map<String, dynamic> _item(
  int id,
  int ts, {
  String text = 'note',
  bool deleted = false,
  int? edited,
  Object? replyTo,
  bool e2e = false,
}) => {
  'id': id,
  'ts': ts,
  'from': 'Ann',
  'text': text,
  'kind': 'chat',
  'deleted': deleted,
  'editedTs': edited,
  'replyTo': replyTo,
  if (e2e) 'e2e': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase db;
  late _Socket socket;
  late _E2e e2e;
  late MessageRepository repo;

  setUp(() async {
    final raw = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: AppDatabase.schemaVersion,
        onCreate: (d, _) => AppDatabase.migrate(d, 0, AppDatabase.schemaVersion),
      ),
    );
    db = AppDatabase.withDatabase(raw);
    socket = _Socket();
    e2e = _E2e();
    repo = MessageRepository(
      db,
      _Session(),
      socket,
      _Conversations(),
      _Policy(),
      e2e,
    )..onInit();
  });

  tearDown(() async {
    await socket.controller.close();
    await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

  Future<void> emit(Map<String, dynamic> e) async {
    socket.controller.add(e);
    await settle();
  }

  Future<List<Message>> notes() => repo.readFor('org', 'Ann', 'self');

  Future<int> count(String table, [String where = '1=1']) async {
    final rows = await db.query('SELECT COUNT(*) AS n FROM $table WHERE $where');
    return rows.first['n'] as int;
  }

  group('events', () {
    test('self_message adds a note of mine', () async {
      await emit({'type': 'self_message', 'id': 7, 'ts': 100, 'text': 'hello'});
      final list = await notes();
      expect(list.map((m) => m.msgId), ['7']);
      expect(list.single.text, 'hello');
      expect(list.single.isMine, isTrue);
      expect(list.single.status, MessageStatus.sent);
    });

    test('the same id never adds twice', () async {
      final e = {'type': 'self_message', 'id': 7, 'ts': 100, 'text': 'hello'};
      await emit(e);
      await emit(e);
      expect(await notes(), hasLength(1));
    });

    test('an unknown field does not break parsing; sd_event shape works', () async {
      await emit({
        'type': 'self_message',
        'id': 7,
        'ts': 100,
        'text': 'a',
        'brandNew': {'x': 1},
      });
      await emit({
        'type': 'sd_event',
        'event': 'self_message',
        'data': {'id': 8, 'ts': 200, 'text': 'b', 'more': [1]},
      });
      expect((await notes()).map((m) => m.text), ['a', 'b']);
    });

    test('self_edited updates the text and marks it edited', () async {
      await emit({'type': 'self_message', 'id': 7, 'ts': 100, 'text': 'old'});
      await emit({
        'type': 'self_edited',
        'messageId': 7,
        'text': 'new',
        'editedTs': 150,
      });
      final m = (await notes()).single;
      expect(m.text, 'new');
      expect(m.editedTs, 150);
    });

    test('self_deleted marks the row deleted, as other chats do', () async {
      await emit({'type': 'self_message', 'id': 7, 'ts': 100, 'text': 'x'});
      await emit({'type': 'self_deleted', 'messageId': 7});
      expect((await notes()).single.isDeleted, isTrue);
    });

    test('an edit or delete never touches a message of another chat', () async {
      await emit({'type': 'private', 'id': 50, 'ts': 5, 'from': 'bob', 'text': 'hi'});
      await emit({'type': 'self_deleted', 'messageId': 50});
      await emit({'type': 'self_edited', 'messageId': 50, 'text': 'z', 'editedTs': 9});
      final rows = await db.query("SELECT text, is_deleted FROM messages WHERE msg_id = '50'");
      expect(rows.single['is_deleted'], 0);
      expect(rows.single['text'], 'hi');
    });

    test('self_ack is accepted and ignored; the next event still arrives', () async {
      await emit({'type': 'self_ack', 'id': 9, 'ts': 1, 'status': 'delivered', 'cid': 'm-1'});
      expect(await notes(), isEmpty);
      await emit({'type': 'self_message', 'id': 7, 'ts': 100, 'text': 'x'});
      expect(await notes(), hasLength(1));
    });

    test('notes are not a chat: no list row, no unread, no preview', () async {
      await emit({'type': 'self_message', 'id': 7, 'ts': 100, 'text': 'x'});
      await emit({'type': 'self_edited', 'messageId': 7, 'text': 'y', 'editedTs': 2});
      expect(await count('conversations'), 0);
      expect(await count('outbox'), 0);
    });

    test('a note sent while the phone was offline arrives with the history sync', () async {
      socket.connection.value = SocketState.offline;
      await emit({'type': 'self_message', 'id': 7, 'ts': 100, 'text': 'x'});
      expect(await notes(), hasLength(1)); // the one it had
      socket.history['/history self'] = {
        'scope': 'self',
        'now': 500,
        'list': [_item(7, 100, text: 'x'), _item(8, 200, text: 'missed')],
      };
      socket.connection.value = SocketState.online;
      await repo.syncSelf();
      expect((await notes()).map((m) => m.msgId), ['7', '8']);
    });
  });

  group('history', () {
    test('the newest page is read with "/history self" (no name)', () async {
      socket.history['/history self'] = {
        'scope': 'self',
        'now': 500,
        'list': [_item(1, 10), _item(2, 20)],
      };
      await repo.syncSelf();
      expect(socket.sent, ['/history self']);
      expect(await notes(), hasLength(2));
      expect(await count('conversations'), 0);
    });

    test('empty history completes with no rows and no error', () async {
      socket.history['/history self'] = {'scope': 'self', 'now': 5, 'list': []};
      await repo.syncSelf();
      expect(await notes(), isEmpty);
    });

    test('a history row and a live event for the same note are one row', () async {
      await emit({'type': 'self_message', 'id': 20, 'ts': 200, 'text': 'x'});
      socket.history['/history self'] = {
        'scope': 'self',
        'now': 500,
        'list': [_item(19, 190), _item(20, 200, text: 'x')],
      };
      await repo.syncSelf();
      expect((await notes()).map((m) => m.msgId), ['19', '20']);
    });

    test('rows come back ordered by the server ts only', () async {
      socket.history['/history self'] = {
        'scope': 'self',
        'now': 500,
        'list': [_item(3, 300), _item(1, 100), _item(2, 200)],
      };
      await repo.syncSelf();
      expect((await notes()).map((m) => m.ts), [100, 200, 300]);
    });

    test('pages back with "before" until the last known id is found', () async {
      await emit({'type': 'self_message', 'id': 5, 'ts': 50, 'text': 'mine'});
      socket.history['/history self'] = {
        'scope': 'self',
        'now': 500,
        'list': [_item(10, 100), _item(11, 110)],
      };
      socket.history['/history self before 10'] = {
        'scope': 'self',
        'now': 500,
        'before': 10,
        'hasMore': true,
        'next': 6,
        'list': [_item(5, 50, text: 'mine'), _item(9, 90)],
      };
      await repo.syncSelf();
      expect(socket.sent, ['/history self', '/history self before 10']);
      expect((await notes()).map((m) => m.msgId), ['5', '9', '10', '11']);
    });

    test('after a first sync the delta since the last stored ts fetches '
        'older edits and deletes', () async {
      socket.history['/history self'] = {
        'scope': 'self',
        'now': 500,
        'list': [_item(1, 10), _item(2, 20)],
      };
      await repo.syncSelf();
      socket.sent.clear();
      socket.history['/history self'] = {
        'scope': 'self',
        'now': 900,
        'list': [_item(1, 10), _item(2, 20)],
      };
      socket.history['/history self delta 2 500'] = {
        'scope': 'self',
        'now': 900,
        'delta': true,
        'window': [1, 2],
        'list': [
          _item(1, 10, text: 'edited', edited: 600),
          _item(2, 20, deleted: true),
        ],
      };
      await repo.syncSelf();
      expect(socket.sent, ['/history self', '/history self delta 2 500']);
      final list = await notes();
      expect(list.first.text, 'edited');
      expect(list.first.editedTs, 600);
      expect(list.last.isDeleted, isTrue);
      final cursor = await db.query('SELECT last_server_id, last_history_now FROM sync_cursor');
      expect(cursor.single['last_server_id'], '2');
      expect(cursor.single['last_history_now'], 900);
    });

    test('a reply keeps the id of the quoted note', () async {
      socket.history['/history self'] = {
        'scope': 'self',
        'now': 5,
        'list': [_item(1, 10), _item(2, 20, replyTo: 1)],
      };
      await repo.syncSelf();
      expect((await notes()).last.replyTo, '1');
    });

    test('the notes are read from SQLite with no network and no command', () async {
      socket.history['/history self'] = {
        'scope': 'self',
        'now': 5,
        'list': [_item(1, 10)],
      };
      await repo.syncSelf();
      socket.sent.clear();
      socket.connection.value = SocketState.offline;
      final list = await repo.openSelf();
      expect(list.map((m) => m.msgId), ['1']);
      expect(socket.sent, isEmpty);
    });

    test('sign-out wipes the notes with the other rows', () async {
      await emit({'type': 'self_message', 'id': 7, 'ts': 100, 'text': 'x'});
      await db.wipeScope('org', 'Ann');
      expect(await notes(), isEmpty);
      expect(await count('sync_cursor'), 0);
    });
  });

  group('targets', () {
    test('self has no name', () {
      expect(ConversationRepository.kindOf('self'), 'self');
      expect(ConversationRepository.targetOf('self'), '');
      expect(ConversationRepository.targetOf('global'), '');
      expect(ConversationRepository.targetOf('dm:bob'), 'bob');
      expect(ConversationRepository.targetOf('group:a:b'), 'a:b');
      expect(SelfConversation.isSelf('self'), isTrue);
      expect(SelfConversation.isSelf('dm:self'), isFalse);
    });
  });

  group('encryption', () {
    const envelope = 'e2e1:{"v":1}';

    test('an envelope that opens shows its text, with the lock', () async {
      e2e.reading = const E2eReading.ok('secret');
      await emit({'type': 'self_message', 'id': 7, 'ts': 100, 'text': envelope});
      await repo.settleDecrypt();
      final m = (await notes()).single;
      expect(m.isEncrypted, isTrue);
      expect(m.isEncryptedUnsupported, isFalse);
      expect(m.text, 'secret');
    });

    test('one that cannot be opened is a locked row, nothing crashes', () async {
      e2e.reading = const E2eReading.cannot('not_for_this_device');
      await emit({'type': 'self_message', 'id': 7, 'ts': 100, 'text': envelope});
      await repo.settleDecrypt();
      await emit({'type': 'self_message', 'id': 8, 'ts': 200, 'text': 'plain'});
      final list = await notes();
      expect(list.first.isEncryptedUnsupported, isTrue);
      expect(list.first.unreadableCode, 'not_for_this_device');
      expect(list.last.text, 'plain');
    });

    test('an edit that arrives as an envelope is opened again', () async {
      await emit({'type': 'self_message', 'id': 7, 'ts': 100, 'text': 'old'});
      e2e.reading = const E2eReading.ok('after');
      await emit({'type': 'self_edited', 'messageId': 7, 'text': envelope, 'editedTs': 3});
      await repo.settleDecrypt();
      expect((await notes()).single.text, 'after');
    });

    test('the expected label of self is self:<me lowercase>', () {
      final real = E2eRepository(E2eKeyStore(), socket, _Session(), db);
      expect(real.expectedConv('self'), 'self:ann');
      expect(real.expectedConv('dm:bob'), 'dm:ann|bob');
    });

    test('a real envelope for self:<me> opens with the keys, and not for '
        'another conversation or another device', () async {
      final crypto = E2eCrypto();
      final mine = await crypto.generateDeviceKeys();
      final other = await crypto.generateDeviceKeys();
      final real = E2eRepository(E2eKeyStore(), socket, _Session(), db);
      Future<String?> signKey(String user, String dev) async =>
          dev == mine.id ? mine.signPub : null;
      final sealed = await crypto.buildEnvelope(
        user: 'ann',
        keys: mine,
        conv: E2eCrypto.selfLabel('Ann'),
        recipients: [mine.asPublic],
        text: 'a private note',
      );
      final ok = await real.open(
        text: sealed,
        convId: 'self',
        keys: mine,
        signKeyFor: signKey,
      );
      expect(ok.state, E2eReadState.ok);
      expect(ok.text, 'a private note');

      final noBox = await real.open(
        text: sealed,
        convId: 'self',
        keys: other,
        signKeyFor: signKey,
      );
      expect(noBox.state, isNot(E2eReadState.ok));
      expect(noBox.code, 'not_for_this_device');

      final wrong = await crypto.buildEnvelope(
        user: 'ann',
        keys: mine,
        conv: E2eCrypto.selfLabel('bob'),
        recipients: [mine.asPublic],
        text: 'x',
      );
      final bad = await real.open(
        text: wrong,
        convId: 'self',
        keys: mine,
        signKeyFor: signKey,
      );
      expect(bad.code, 'wrong_conversation');
    });
  });

  group('nothing can be sent into self', () {
    test('queueing a message throws in a debug build and writes nothing', () async {
      await expectLater(
        repo.sendText('self', 'hello'),
        throwsA(isA<StateError>()),
      );
      expect(await count('outbox'), 0);
      expect(await count('messages'), 0);
      expect(socket.sent, isEmpty);
    });

    test('an edit of a note throws and queues nothing', () async {
      await emit({'type': 'self_message', 'id': 7, 'ts': 100, 'text': 'x'});
      await expectLater(repo.editText('7', 'y'), throwsA(isA<StateError>()));
      expect(await count('outbox'), 0);
    });

    test('no wire line exists for self, whatever the entry kind', () {
      for (final kind in ['message', 'reply', 'edit']) {
        final entry = OutboxEntry(
          id: 1,
          convId: 'self',
          kind: kind,
          payload: const {'text': 'x', 'replyTo': '3'},
          refId: 'temp-1',
          status: 'pending',
          retryCount: 0,
          nextAttemptTs: 0,
          createdTs: 0,
          cid: 'm-1',
        );
        expect(() => MessageRepository.wireCommand(entry), throwsStateError);
      }
      expect(
        () => MessageRepository.cidCommand('self', 'x', 'm-1'),
        throwsStateError,
      );
    });

    test('in a release build the attempt is refused with a log line', () {
      expect(SelfConversation.refuse('self', 'sendText', isDebug: false), isTrue);
      expect(SelfConversation.refuse('dm:bob', 'sendText', isDebug: false), isFalse);
      expect(
        () => SelfConversation.refuse('self', 'sendText', isDebug: true),
        throwsStateError,
      );
    });

    test('other conversations are not affected by the guard', () async {
      expect(SelfConversation.refuse('global', 'x'), isFalse);
      final entry = OutboxEntry(
        id: 1,
        convId: 'dm:bob',
        kind: 'message',
        payload: const {'text': 'x'},
        refId: 'temp-1',
        status: 'pending',
        retryCount: 0,
        nextAttemptTs: 0,
        createdTs: 0,
        cid: 'm-1',
      );
      expect(MessageRepository.wireCommand(entry), '/c m-1 /msg bob x');
    });
  });
}
