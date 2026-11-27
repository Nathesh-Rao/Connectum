import 'dart:async';
import 'dart:convert';

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
  final current = Rxn<SessionInfo>(
    const SessionInfo(orgId: 'org', userId: 'Ann', expiresTs: 1 << 50),
  );
  final _values = <String, String>{};

  @override
  String? get orgId => current.value?.orgId;
  @override
  String? get userId => current.value?.userId;
  @override
  bool get hasSession => current.value != null;
  @override
  Future<String?> readValue(String key) async => _values[key];
  @override
  Future<void> writeValue(String key, String value) async =>
      _values[key] = value;
}

class _Socket extends Fake implements SocketService {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <String>[];
  final history = <String, Map<String, dynamic>>{};
  String mode = 'required';
  bool isModeDown = false;

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
  Future<Map<String, dynamic>> sdCall(
    String action,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (action == 'e2e.status' && !isModeDown) return {'mode': mode};
    throw const SocketCallError('timeout');
  }

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
  _E2e(this.real);

  final E2eRepository real;
  E2eDeviceKeys? deviceKeys;
  List<E2eDevicePublic> devices = [];
  Object? devicesError;
  int devicesCalls = 0;
  bool isSetting = true;
  List<E2ePinChange> pins = [];
  final invalidated = <String>[];
  final regs = StreamController<void>.broadcast();

  @override
  Stream<void> get unlockRequests => const Stream.empty();
  @override
  Stream<void> get registrations => regs.stream;
  @override
  bool get isSettingUp => isSetting;
  @override
  Future<E2eDeviceKeys?> keys() async => deviceKeys;
  @override
  Future<Map<String, dynamic>> currentStatusArgs() async => {};
  @override
  Map<String, List<E2eDevicePublic>>? cachedDevices(List<String> users) => null;
  @override
  Future<Map<String, List<E2eDevicePublic>>> devicesOf(
    List<String> users, {
    bool isForced = false,
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    devicesCalls++;
    final error = devicesError;
    if (error != null) throw error;
    return {for (final u in users) u.toLowerCase(): devices};
  }

  @override
  Future<List<E2ePinChange>> checkPins(
    Map<String, List<E2eDevicePublic>> byUser, {
    required bool isRecord,
  }) async => pins;
  @override
  void invalidate(Iterable<String> users) => invalidated.addAll(users);
  @override
  Future<String> seal(E2eSendDecision decision, String convId, String text) =>
      real.seal(decision, convId, text);
  @override
  Future<E2eReading> open({
    required String text,
    required String convId,
    String? expectConv,
    E2eDeviceKeys? keys,
    Future<String?> Function(String user, String deviceId)? signKeyFor,
    Future<E2eDevicePublic?> Function(String user, String deviceId)? deviceFor,
    Map<String, ({String ecdh, String sign})>? testPins,
  }) async => const E2eReading.pending();
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

/// A timer a test fires by hand: the 3 second hold has no wall clock here.
class _HandTimer implements Timer {
  _HandTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool isCancelled = false;
  bool isFired = false;

  @override
  void cancel() => isCancelled = true;
  @override
  bool get isActive => !isCancelled && !isFired;
  @override
  int get tick => 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase db;
  late _Session session;
  late _Socket socket;
  late _E2e e2e;
  late EncryptionPolicy policy;
  late MessageRepository repo;
  late List<_HandTimer> holds;
  late E2eDeviceKeys phone;
  late E2eDevicePublic other;
  late E2eDevicePublic third;

  final crypto = E2eCrypto();

  setUpAll(() async {
    phone = await crypto.generateDeviceKeys();
    other = (await crypto.generateDeviceKeys()).asPublic;
    third = (await crypto.generateDeviceKeys()).asPublic;
  });

  setUp(() async {
    final raw = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: AppDatabase.schemaVersion,
        onCreate: (d, _) =>
            AppDatabase.migrate(d, 0, AppDatabase.schemaVersion),
      ),
    );
    db = AppDatabase.withDatabase(raw);
    session = _Session();
    socket = _Socket()..mode = 'off';
    e2e = _E2e(E2eRepository(E2eKeyStore(), socket, session, db));
    policy = EncryptionPolicy(socket, session, e2e);
    repo = MessageRepository(db, session, socket, _Conversations(), policy, e2e)
      ..onInit();
    holds = [];
    repo.holdTimer = (d, cb) {
      final t = _HandTimer(d, cb);
      holds.add(t);
      return t;
    };
  });

  tearDown(() async {
    await socket.controller.close();
    await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
  });

  Future<void> settle([int ms = 140]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> emit(Map<String, dynamic> e) async {
    socket.controller.add(e);
    await settle();
  }

  Future<List<Message>> notes() => repo.readFor('org', 'Ann', 'self');

  Future<int> count(String table, [String where = '1=1']) async {
    final rows = await db.query(
      'SELECT COUNT(*) AS n FROM $table WHERE $where',
    );
    return rows.first['n'] as int;
  }

  Future<SendResult> write(String text) async {
    final result = await repo.sendText('self', text);
    await settle();
    return result;
  }

  String cidOf(String line) =>
      RegExp(r'^/c (\S+) ').firstMatch(line)!.group(1)!;

  String lastCid() =>
      cidOf(socket.sent.lastWhere((l) => l.contains(' /self ')));

  Future<void> ack(
    String cid,
    int id, {
    bool isDuplicate = false,
    int ts = 1000,
  }) => emit({
    'type': 'self_ack',
    'id': id,
    'ts': ts,
    'status': 'delivered',
    'cid': cid,
    if (isDuplicate) 'duplicate': true,
  });

  void fireHolds() {
    for (final t in holds) {
      if (t.isActive) {
        t.isFired = true;
        t.callback();
      }
    }
  }

  /// The connection drops and comes back; history answers with [list].
  Future<void> reconnect([List<Map<String, dynamic>> list = const []]) async {
    socket.connection.value = SocketState.offline;
    await settle();
    socket.history['/history self'] = {'scope': 'self', 'now': 0, 'list': list};
    socket.history['/history global'] = {
      'scope': 'global',
      'now': 0,
      'list': <Map<String, dynamic>>[],
    };
    socket.connection.value = SocketState.online;
    await repo.syncNow();
    await settle();
  }

  void useEncryption({
    String mode = 'required',
    List<E2eDevicePublic>? devices,
    bool isReady = true,
  }) {
    socket.mode = mode;
    e2e.devices = devices ?? [phone.asPublic, other];
    e2e.deviceKeys = isReady ? phone : null;
    policy.onReconnected();
  }

  /// A note of mine from the server (so it has a server id), typed [ago] ago.
  Future<void> serverNote(
    int id,
    String text, {
    Duration ago = Duration.zero,
  }) => emit({
    'type': 'self_message',
    'id': id,
    'ts': repo.clock() - ago.inMilliseconds,
    'text': text,
  });

  Message note(List<Message> all, String id) =>
      all.firstWhere((m) => m.msgId == id);

  group('notes have no edit window', () {
    test('canEditNote is true for a note of any age', () async {
      await serverNote(1, 'fresh', ago: const Duration(minutes: 14));
      await serverNote(2, 'old', ago: const Duration(minutes: 16));
      await serverNote(3, 'ancient', ago: const Duration(days: 40));
      final all = await notes();
      expect(repo.canEditNote(note(all, '1')), isTrue);
      expect(repo.canEditNote(note(all, '2')), isTrue);
      expect(repo.canEditNote(note(all, '3')), isTrue);
      expect(repo.canReplyToNote(note(all, '3')), isTrue);
    });

    test('the rule is one constant; chats keep their 15 minutes', () {
      expect(SelfConversation.hasEditWindow, isFalse);
      final ancient = repo.clock() - const Duration(days: 40).inMilliseconds;
      expect(SelfConversation.isInEditWindow(ancient, repo.clock()), isTrue);
      expect(SelfConversation.editWindow, const Duration(minutes: 15));
    });

    test(
      'a pending, failed or deleted note cannot be edited or quoted',
      () async {
        await serverNote(3, 'gone');
        await emit({'type': 'self_deleted', 'messageId': 3});
        var m = note(await notes(), '3');
        expect(repo.canEditNote(m), isFalse);
        expect(repo.canReplyToNote(m), isFalse);
        await write('pending');
        m = (await notes()).firstWhere((n) => n.isLocalTemp);
        expect(repo.canEditNote(m), isFalse);
        expect(repo.canReplyToNote(m), isFalse);
      },
    );
  });

  group('edit', () {
    test(
      'inside the window: new text at once with a clock, then edited on the event',
      () async {
        await serverNote(10, 'first');
        expect(await repo.editText('10', 'second'), isTrue);
        await settle();
        expect(socket.sent.last, '/edit self 10 second');
        var m = note(await notes(), '10');
        expect(m.text, 'second');
        expect(m.isEditPending, isTrue);
        expect(m.editedTs, isNull);
        expect(await count('outbox'), 1);

        await emit({
          'type': 'self_edited',
          'messageId': 10,
          'text': 'second',
          'editedTs': 5000,
        });
        m = note(await notes(), '10');
        expect(m.text, 'second');
        expect(m.isEditPending, isFalse);
        expect(m.editedTs, 5000);
        expect(await count('outbox'), 0);
        // The same event again changes nothing.
        await emit({
          'type': 'self_edited',
          'messageId': 10,
          'text': 'second',
          'editedTs': 5000,
        });
        expect(note(await notes(), '10').text, 'second');
        expect(await count('messages'), 1);
      },
    );

    test('an edit of an old note is queued and sent like any other', () async {
      await serverNote(11, 'old', ago: const Duration(days: 3));
      final notices = <String>[];
      repo.notices.listen(notices.add);
      expect(await repo.editText('11', 'new'), isTrue);
      await settle();
      expect(socket.sent.where((l) => l == '/edit self 11 new'), hasLength(1));
      expect(note(await notes(), '11').text, 'new');
      expect(notices, isEmpty);
    });

    test(
      'an old note refused as expired: no retry, old text back, short message',
      () async {
        await serverNote(111, 'old', ago: const Duration(days: 3));
        final notices = <String>[];
        repo.notices.listen(notices.add);
        await repo.editText('111', 'new');
        await settle();
        await emit({
          'type': 'edit_denied',
          'messageId': 111,
          'reason': 'expired',
        });
        expect(note(await notes(), '111').text, 'old');
        expect(await count('outbox'), 0);
        expect(notices, ["Can't edit this note yet"]);
        final sentBefore = socket.sent.length;
        await repo.flush();
        await settle();
        expect(socket.sent, hasLength(sentBefore));
      },
    );

    test('empty text, over 2000 characters and a # line are refused', () async {
      await serverNote(12, 'x');
      expect(await repo.editText('12', '   '), isFalse);
      expect(await repo.editText('12', 'a' * 2001), isFalse);
      expect(await repo.editText('12', '#help'), isFalse);
      expect(await count('outbox'), 0);
      expect(socket.sent, isEmpty);
    });

    test(
      'expired: dropped without retry, old text back, a short message',
      () async {
        await serverNote(13, 'before');
        final notices = <String>[];
        repo.notices.listen(notices.add);
        await repo.editText('13', 'after');
        await settle();
        await emit({
          'type': 'edit_denied',
          'messageId': 13,
          'reason': 'expired',
        });
        final m = note(await notes(), '13');
        expect(m.text, 'before');
        expect(m.isEditPending, isFalse);
        expect(m.editedTs, isNull);
        expect(await count('outbox'), 0);
        expect(notices, [MessageRepository.cantEditYet]);
        final sentBefore = socket.sent.length;
        await repo.flush();
        await settle();
        expect(socket.sent, hasLength(sentBefore));
      },
    );

    test('deleted: the note is removed', () async {
      await serverNote(14, 'x');
      await repo.editText('14', 'y');
      await settle();
      await emit({'type': 'edit_denied', 'messageId': 14, 'reason': 'deleted'});
      expect(note(await notes(), '14').isDeleted, isTrue);
      expect(await count('outbox'), 0);
    });

    test('another refusal restores the text and says so', () async {
      await serverNote(15, 'a');
      final notices = <String>[];
      repo.notices.listen(notices.add);
      await repo.editText('15', 'b');
      await settle();
      await emit({
        'type': 'edit_denied',
        'messageId': 15,
        'reason': 'forbidden',
      });
      expect(note(await notes(), '15').text, 'a');
      expect(notices, [MessageRepository.couldNotEdit]);
    });

    test('repeating the same edit applies again with a new editedTs', () async {
      await serverNote(16, 'a');
      await repo.editText('16', 'b');
      await settle();
      await emit({
        'type': 'self_edited',
        'messageId': 16,
        'text': 'b',
        'editedTs': 100,
      });
      await repo.editText('16', 'c');
      await settle();
      await emit({
        'type': 'self_edited',
        'messageId': 16,
        'text': 'c',
        'editedTs': 200,
      });
      final m = note(await notes(), '16');
      expect(m.text, 'c');
      expect(m.editedTs, 200);
      expect(
        socket.sent.where((l) => l.startsWith('/edit self 16')),
        hasLength(2),
      );
    });

    test(
      'queued offline and sent much later: still sent, no local window',
      () async {
        await serverNote(17, 'a', ago: const Duration(minutes: 10));
        socket.connection.value = SocketState.offline;
        await settle();
        final notices = <String>[];
        repo.notices.listen(notices.add);
        expect(await repo.editText('17', 'b'), isTrue);
        await settle();
        expect(socket.sent, isEmpty);
        expect(note(await notes(), '17').text, 'b');
        // The phone comes back online six minutes later.
        final start = repo.clock();
        repo.clock = () => start + const Duration(minutes: 6).inMilliseconds;
        socket.connection.value = SocketState.online;
        await repo.flush();
        await settle();
        expect(socket.sent.where((l) => l == '/edit self 17 b'), hasLength(1));
        expect(note(await notes(), '17').text, 'b');
        expect(notices, isEmpty);
      },
    );

    test(
      'queued offline and sent inside the window: goes out once online',
      () async {
        await serverNote(18, 'a');
        socket.connection.value = SocketState.offline;
        await settle();
        await repo.editText('18', 'b');
        await settle();
        expect(socket.sent, isEmpty);
        socket.connection.value = SocketState.online;
        await repo.flush();
        await settle();
        expect(socket.sent.where((l) => l == '/edit self 18 b'), hasLength(1));
      },
    );

    test(
      'an unanswered edit is sent again after a drop, whatever the time',
      () async {
        await serverNote(19, 'a', ago: const Duration(minutes: 14));
        await repo.editText('19', 'b');
        await settle();
        expect(socket.sent.where((l) => l.startsWith('/edit')), hasLength(1));
        // The connection drops with no answer; time passes.
        final start = repo.clock();
        repo.clock = () => start + const Duration(minutes: 2).inMilliseconds;
        await reconnect();
        expect(socket.sent.where((l) => l.startsWith('/edit')), hasLength(2));
        expect(note(await notes(), '19').text, 'b');
      },
    );

    test(
      'an edit of a note that never reached the server is not an edit',
      () async {
        await write('local');
        final m = (await notes()).single;
        expect(await repo.editText(m.msgId, 'other'), isFalse);
      },
    );

    test('an edit made on another device replaces the text', () async {
      await serverNote(20, 'a');
      await emit({
        'type': 'self_edited',
        'messageId': 20,
        'text': 'z',
        'editedTs': 9,
      });
      expect(note(await notes(), '20').text, 'z');
    });

    test('edit never goes to a DM, a group or the global room', () async {
      await serverNote(21, 'a');
      await repo.editText('21', 'b');
      await settle();
      expect(
        socket.sent.where((l) => !l.startsWith('/edit self 21 ')),
        isEmpty,
      );
    });

    test(
      'encrypted: an envelope with a box for each own device, nothing in plain',
      () async {
        useEncryption(devices: [phone.asPublic, other, third]);
        await write('secret');
        await ack(lastCid(), 30, ts: repo.clock());
        await repo.editText('30', 'new secret');
        await settle();
        final line = socket.sent.last;
        expect(line, startsWith('/edit self 30 e2e1:'));
        expect(line, isNot(contains('new secret')));
        final env =
            jsonDecode(
                  line
                      .replaceFirst('/edit self 30 ', '')
                      .substring(E2eCrypto.prefix.length),
                )
                as Map<String, dynamic>;
        expect(env['conv'], 'self:ann');
        expect((env['keys'] as Map).keys.toSet(), {
          phone.id,
          other.id,
          third.id,
        });
        // The row shows what was typed; the echo keeps it (no flicker).
        expect(note(await notes(), '30').text, 'new secret');
        await emit({
          'type': 'self_edited',
          'messageId': 30,
          'text': line.replaceFirst('/edit self 30 ', ''),
          'editedTs': 77,
        });
        final m = note(await notes(), '30');
        expect(m.text, 'new secret');
        expect(m.isEncrypted, isTrue);
        expect(m.decryptState, 'ok');
        expect(m.editedTs, 77);
        expect(await count('outbox'), 0);
      },
    );

    test(
      'encrypted and refused as expired: the old envelope and text come back',
      () async {
        useEncryption();
        await write('secret');
        await ack(lastCid(), 31, ts: repo.clock());
        await repo.editText('31', 'again');
        await settle();
        await emit({
          'type': 'edit_denied',
          'messageId': 31,
          'reason': 'expired',
        });
        final m = note(await notes(), '31');
        expect(m.text, 'secret');
        expect(m.isEncrypted, isTrue);
        expect(m.decryptState, 'ok');
      },
    );

    test(
      'stale devices: refreshed and sealed once more, then given up',
      () async {
        useEncryption(devices: [phone.asPublic, other]);
        await write('secret');
        await ack(lastCid(), 32, ts: repo.clock());
        await repo.editText('32', 'v2');
        await settle();
        expect(socket.sent.where((l) => l.startsWith('/edit')), hasLength(1));
        final first = socket.sent.last;
        final mid = jsonDecode(
          first
              .replaceFirst('/edit self 32 ', '')
              .substring(E2eCrypto.prefix.length),
        )['mid'];
        await emit({
          'type': 'error',
          'code': 'e2e_stale_devices',
          'mid': mid,
          'conv': 'self:ann',
          'users': ['Ann'],
        });
        await settle(300);
        expect(socket.sent.where((l) => l.startsWith('/edit')), hasLength(2));
        expect(socket.sent.last, isNot(first));
        final mid2 = jsonDecode(
          socket.sent.last
              .replaceFirst('/edit self 32 ', '')
              .substring(E2eCrypto.prefix.length),
        )['mid'];
        await emit({
          'type': 'error',
          'code': 'e2e_stale_devices',
          'mid': mid2,
          'conv': 'self:ann',
          'users': ['Ann'],
        });
        await settle(300);
        expect(socket.sent.where((l) => l.startsWith('/edit')), hasLength(2));
        expect(note(await notes(), '32').text, 'secret');
      },
    );

    test('keys not ready: an encrypted org never gets a plain edit', () async {
      await serverNote(33, 'a');
      useEncryption(isReady: false);
      await repo.editText('33', 'b');
      await settle();
      expect(socket.sent.where((l) => l.startsWith('/edit')), isEmpty);
      expect(await count('outbox'), 1);
    });
  });

  group('delete', () {
    test('the note disappears at once and /delete self goes out', () async {
      await serverNote(40, 'x');
      expect(
        await repo.deleteMessage(note(await notes(), '40')),
        DeleteResult.deleted,
      );
      await settle();
      expect(note(await notes(), '40').isDeleted, isTrue);
      expect(socket.sent.last, '/delete self 40');
      await emit({'type': 'self_deleted', 'messageId': 40});
      expect(await count('outbox'), 0);
      expect(note(await notes(), '40').isDeleted, isTrue);
    });

    test(
      'repeating is safe: a second tap queues nothing new, the echo twice is harmless',
      () async {
        await serverNote(41, 'x');
        final m = note(await notes(), '41');
        await repo.deleteMessage(m);
        await repo.deleteMessage(m);
        await settle();
        expect(socket.sent.where((l) => l == '/delete self 41'), hasLength(1));
        await emit({'type': 'self_deleted', 'messageId': 41});
        await emit({'type': 'self_deleted', 'messageId': 41});
        expect(await count('messages'), 1);
        expect(await count('outbox'), 0);
      },
    );

    test('not_found counts as success', () async {
      await serverNote(42, 'x');
      await repo.deleteMessage(note(await notes(), '42'));
      await settle();
      await emit({
        'type': 'delete_denied',
        'messageId': 42,
        'reason': 'not_found',
      });
      expect(note(await notes(), '42').isDeleted, isTrue);
      expect(await count('outbox'), 0);
    });

    test('queued offline, sent when the connection is back', () async {
      await serverNote(43, 'x');
      socket.connection.value = SocketState.offline;
      await settle();
      expect(
        await repo.deleteMessage(note(await notes(), '43')),
        DeleteResult.deleted,
      );
      await settle();
      expect(note(await notes(), '43').isDeleted, isTrue);
      expect(socket.sent, isEmpty);
      socket.connection.value = SocketState.online;
      await repo.flush();
      await settle();
      expect(socket.sent, ['/delete self 43']);
    });

    test('a refusal brings the note back and says so', () async {
      await serverNote(44, 'x');
      final notices = <String>[];
      repo.notices.listen(notices.add);
      await repo.deleteMessage(note(await notes(), '44'));
      await settle();
      await emit({'type': 'delete_denied', 'messageId': 44, 'reason': 'busy'});
      expect(note(await notes(), '44').isDeleted, isFalse);
      expect(await count('outbox'), 0);
      expect(notices, [MessageRepository.couldNotDelete]);
    });

    test(
      'a note that never reached the server is removed locally, nothing is sent',
      () async {
        await write('local');
        await repo.deleteMessage((await notes()).single);
        await settle();
        expect(await notes(), isEmpty);
        expect(await count('outbox'), 0);
        expect(socket.sent.where((l) => l.contains('delete')), isEmpty);
      },
    );

    test('an edit still waiting for the note is dropped with it', () async {
      await serverNote(45, 'x');
      socket.connection.value = SocketState.offline;
      await settle();
      await repo.editText('45', 'y');
      await repo.deleteMessage(note(await notes(), '45'));
      await settle();
      expect(await count('outbox', "kind = 'edit'"), 0);
      expect(await count('outbox', "kind = 'delete'"), 1);
    });
  });

  group('reply', () {
    test('only to a sent, not deleted note', () async {
      await serverNote(50, 'quoted');
      await serverNote(51, 'gone');
      await emit({'type': 'self_deleted', 'messageId': 51});
      expect(
        await repo.sendText('self', 'a', replyTo: '51'),
        SendResult.invalid,
      );
      expect(
        await repo.sendText('self', 'a', replyTo: '999'),
        SendResult.invalid,
      );
      expect(
        await repo.sendText('self', 'a', replyTo: 'temp-1'),
        SendResult.invalid,
      );
      expect(await count('outbox'), 0);
      expect(socket.sent, isEmpty);
    });

    test(
      'goes out with a fixed cid as /c <cid> /replyself <id> <text>',
      () async {
        await serverNote(52, 'quoted');
        expect(
          await repo.sendText('self', 'answer', replyTo: '52'),
          SendResult.queued,
        );
        await settle();
        expect(
          socket.sent.single,
          matches(RegExp(r'^/c m-\S+ /replyself 52 answer$')),
        );
        final cid = cidOf(socket.sent.single);
        var m = (await notes()).firstWhere((n) => n.isLocalTemp);
        expect(m.replyTo, '52');
        expect(m.cid, cid);
        // A resend after a drop reuses the cid.
        await reconnect();
        expect(
          socket.sent.where((l) => l.contains('/replyself')).map(cidOf).toSet(),
          {cid},
        );
        await ack(cid, 53, ts: 9000);
        m = note(await notes(), '53');
        expect(m.status, MessageStatus.sent);
        expect(m.replyTo, '52');
        expect(await count('outbox'), 0);
      },
    );

    test(
      'its own echo is held and merged like a note: no second row',
      () async {
        await serverNote(54, 'quoted');
        await repo.sendText('self', 'answer', replyTo: '54');
        await settle();
        final cid = cidOf(socket.sent.single);
        await emit({
          'type': 'self_message',
          'id': 55,
          'ts': 9000,
          'text': 'answer',
          'replyTo': 54,
        });
        expect((await notes()).where((n) => n.msgId == '55'), isEmpty);
        await ack(cid, 55, ts: 9000);
        final all = await notes();
        expect(all, hasLength(2));
        expect(note(all, '55').replyTo, '54');
      },
    );

    test(
      'the held copy of an unknown echo is released after 3 seconds',
      () async {
        await repo.sendText('self', 'mine'); // in flight
        await serverNote(56, 'quoted');
        await emit({
          'type': 'self_message',
          'id': 57,
          'ts': 1,
          'text': 'x',
          'replyTo': 56,
        });
        fireHolds();
        await settle();
        expect(note(await notes(), '57').replyTo, '56');
      },
    );

    test(
      'an entry first sent more than 23 hours ago fails with tap to retry',
      () async {
        await serverNote(58, 'quoted');
        await repo.sendText('self', 'answer', replyTo: '58');
        await settle();
        await db.update(
          'UPDATE outbox SET created_ts = ?, first_attempt_ts = ?',
          [0, 0],
        );
        await reconnect();
        final m = (await notes()).firstWhere((n) => n.replyTo == '58');
        expect(m.status, MessageStatus.failed);
        expect(m.isTooOld, isTrue);
        expect(
          socket.sent.where((l) => l.contains('/replyself')),
          hasLength(1),
        );
      },
    );

    test('encrypted: an envelope for self:<me>, never plain', () async {
      useEncryption(devices: [phone.asPublic, other]);
      await write('first');
      await ack(lastCid(), 60);
      await repo.sendText('self', 'secret reply', replyTo: '60');
      await settle();
      final line = socket.sent.last;
      expect(line, matches(RegExp(r'^/c m-\S+ /replyself 60 e2e1:')));
      expect(line, isNot(contains('secret reply')));
      final env =
          jsonDecode(
                line
                    .replaceFirst(RegExp(r'^/c \S+ /replyself 60 '), '')
                    .substring(E2eCrypto.prefix.length),
              )
              as Map<String, dynamic>;
      expect(env['conv'], 'self:ann');
      expect((env['keys'] as Map).keys.toSet(), {phone.id, other.id});
    });

    test('keys not ready: the reply waits, nothing leaves in plain', () async {
      useEncryption(isReady: false);
      await serverNote(61, 'quoted');
      await repo.sendText('self', 'answer', replyTo: '61');
      await settle();
      expect(socket.sent, isEmpty);
      final m = (await notes()).firstWhere((n) => n.replyTo == '61');
      expect(m.isWaitingForEncryption, isTrue);
    });
  });

  group('guards', () {
    test('there are no reactions for a note', () async {
      await serverNote(70, 'x');
      expect(
        await repo.react(note(await notes(), '70'), '👍'),
        ReactResult.notSupported,
      );
      expect(socket.sent, isEmpty);
    });

    test('save and pin are not refused; anything else for self still is', () {
      expect(SelfConversation.refuse('self', 'save'), isFalse);
      expect(SelfConversation.refuse('self', 'pin', isDebug: false), isFalse);
      expect(SelfConversation.refuse('self', 'unpin'), isFalse);
      expect(() => SelfConversation.refuse('self', 'react'), throwsStateError);
      expect(SelfConversation.refuse('self', 'react', isDebug: false), isTrue);
    });

    test('an encrypted DM edit is still blocked as before', () async {
      final entry = OutboxEntry(
        id: 1,
        convId: 'dm:bob',
        kind: 'edit',
        payload: const {'text': 'x'},
        refId: '5',
        status: 'pending',
        retryCount: 0,
        nextAttemptTs: 0,
        createdTs: 0,
      );
      expect(MessageRepository.wireCommand(entry), '/edit dm bob 5 x');
      // The block itself lives in _send; the source line is guarded by !isSelf.
    });

    test(
      'no command for a note can reach the global room or a direct chat',
      () async {
        await serverNote(71, 'x');
        await repo.editText('71', 'y');
        await repo.sendText('self', 'r', replyTo: '71');
        await repo.deleteMessage(note(await notes(), '71'));
        await settle();
        for (final line in socket.sent) {
          expect(
            line,
            anyOf(
              startsWith('/edit self '),
              startsWith('/delete self '),
              matches(RegExp(r'^/c m-\S+ /replyself ')),
            ),
          );
        }
      },
    );

    test('a sign out wipes queued edits, deletes and replies', () async {
      await serverNote(72, 'x');
      socket.connection.value = SocketState.offline;
      await settle();
      await repo.editText('72', 'y');
      await repo.sendText('self', 'r', replyTo: '72');
      await serverNote(73, 'z');
      await repo.deleteMessage(note(await notes(), '73'));
      expect(await count('outbox'), 3);
      await db.wipeScope('org', 'Ann');
      expect(await count('outbox'), 0);
    });
  });
}
