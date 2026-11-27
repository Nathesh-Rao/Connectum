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

Map<String, dynamic> _item(int id, int ts, {String text = 'note'}) => {
  'id': id,
  'ts': ts,
  'from': 'Ann',
  'text': text,
  'kind': 'chat',
  'deleted': false,
};

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

  Map<String, dynamic> envelopeOf(String line) {
    final text = line.replaceFirst(RegExp(r'^/c \S+ /self '), '');
    expect(E2eCrypto.isEnvelope(text), isTrue, reason: 'not an envelope');
    return jsonDecode(text.substring(E2eCrypto.prefix.length))
        as Map<String, dynamic>;
  }

  group('sending a plain note', () {
    test(
      'goes out as /c <cid> /self, shows pending, then sent on the ack',
      () async {
        expect(await write('hello'), SendResult.queued);
        expect(socket.sent, hasLength(1));
        expect(socket.sent.single, matches(RegExp(r'^/c m-\S+ /self hello$')));
        var rows = await notes();
        expect(rows.single.status, MessageStatus.sending);
        expect(rows.single.isLocalTemp, isTrue);
        expect(rows.single.cid, lastCid());

        await ack(lastCid(), 50, ts: 7000);
        rows = await notes();
        expect(rows.single.msgId, '50');
        expect(rows.single.ts, 7000);
        // A note has no recipient: `delivered` from the server shows as sent.
        expect(rows.single.status, MessageStatus.sent);
        expect(await count('outbox'), 0);
        expect(await count('conversations'), 0);
      },
    );

    test(
      'a note is never posted to the global room, whatever happens',
      () async {
        useEncryption(isReady: false);
        await write('one');
        socket.mode = 'off';
        policy.onReconnected();
        await write('two');
        await repo.flush();
        await settle();
        for (final line in socket.sent) {
          expect(line, matches(RegExp(r'^/c m-\S+ /self ')));
        }
      },
    );

    test(
      'a retry after a lost answer reuses the cid; the repeat ack is a normal ack',
      () async {
        await write('hello');
        final cid = lastCid();
        await reconnect();
        final sends = socket.sent.where((l) => l.contains('/self hello'));
        expect(sends, hasLength(2));
        expect(cidOf(sends.last), cid);
        await ack(cid, 50, isDuplicate: true);
        expect((await notes()).single.msgId, '50');
        expect(await count('outbox'), 0);
      },
    );

    test(
      'more than 2000 characters is refused before anything is written',
      () async {
        expect(await repo.sendText('self', 'a' * 2001), SendResult.tooLong);
        expect(await count('outbox'), 0);
        expect(await count('messages'), 0);
        expect(socket.sent, isEmpty);
        expect(await repo.sendText('self', 'a' * 2000), SendResult.queued);
      },
    );

    test('a # line is a command, never a note', () async {
      expect(await repo.sendText('self', '#help'), SendResult.blocked);
      expect(repo.lastBlock, contains('commands'));
      expect(await count('outbox'), 0);
      expect(socket.sent, isEmpty);
    });

    test(
      'offline: notes wait in order and go out one at a time on reconnect',
      () async {
        socket.connection.value = SocketState.offline;
        await write('A');
        await write('B');
        await write('C');
        expect(socket.sent, isEmpty);
        expect(await count('outbox', "status = 'pending'"), 3);
        expect((await notes()).map((m) => m.text), ['A', 'B', 'C']);
        expect(
          (await notes()).every((m) => m.status == MessageStatus.pending),
          isTrue,
        );

        socket.history['/history self'] = {
          'scope': 'self',
          'now': 0,
          'list': [],
        };
        socket.connection.value = SocketState.online;
        await repo.flush();
        await settle();
        expect(socket.sent, hasLength(1));
        expect(socket.sent.last, endsWith('/self A'));
        await ack(lastCid(), 11);
        expect(socket.sent.last, endsWith('/self B'));
        await ack(lastCid(), 12);
        expect(socket.sent.last, endsWith('/self C'));
        await ack(lastCid(), 13);
        expect((await notes()).map((m) => m.msgId), ['11', '12', '13']);
        expect(await count('outbox'), 0);
      },
    );

    test(
      'a note older than 23 hours is not sent: it fails as "too old"',
      () async {
        socket.connection.value = SocketState.offline;
        await write('old');
        final old = DateTime.now()
            .subtract(const Duration(hours: 24))
            .millisecondsSinceEpoch;
        await db.update('UPDATE outbox SET created_ts = ?', [old]);
        socket.connection.value = SocketState.online;
        await repo.flush();
        await settle();
        expect(socket.sent, isEmpty);
        final m = (await notes()).single;
        expect(m.status, MessageStatus.failed);
        expect(m.isTooOld, isTrue);
        expect(await count('outbox', "status = 'failed'"), 1);

        // The person sends it again: a new note with a new client id.
        final oldCid = m.cid;
        await repo.retry(m.msgId);
        await settle();
        expect(socket.sent, hasLength(1));
        expect(cidOf(socket.sent.single), isNot(oldCid));
        expect(socket.sent.single, endsWith('/self old'));
      },
    );

    test(
      'a note first sent more than 23 hours ago is not sent again',
      () async {
        await write('x');
        final old = DateTime.now()
            .subtract(const Duration(hours: 24))
            .millisecondsSinceEpoch;
        await db.update('UPDATE outbox SET first_attempt_ts = ?', [old]);
        socket.sent.clear();
        await reconnect();
        expect(socket.sent.where((l) => l.contains('/self x')), isEmpty);
        expect((await notes()).single.status, MessageStatus.failed);
      },
    );

    test(
      'a refusal fails the note; tapping retry sends it with the same cid',
      () async {
        await write('hello');
        final cid = lastCid();
        await emit({
          'type': 'error',
          'code': 'e2e_required',
          'text': 'refused',
        });
        var m = (await notes()).single;
        expect(m.status, MessageStatus.failed);
        expect(await count('outbox', "status = 'failed'"), 1);

        await repo.retry(m.msgId);
        await settle();
        expect(socket.sent, hasLength(2));
        expect(cidOf(socket.sent.last), cid);
        await ack(cid, 9);
        m = (await notes()).single;
        expect(m.status, MessageStatus.sent);
      },
    );

    test(
      'sign-out clears queued notes with the other queued messages',
      () async {
        socket.connection.value = SocketState.offline;
        await write('A');
        await write('B');
        expect(await count('outbox'), 2);
        await db.wipeScope('org', 'Ann');
        expect(await count('outbox'), 0);
        expect(await notes(), isEmpty);
      },
    );
  });

  group('matching self_message with the pending note', () {
    test(
      'message, then ack: the held copy is the echo and is dropped',
      () async {
        await write('hello');
        final cid = lastCid();
        await emit({
          'type': 'self_message',
          'id': 50,
          'ts': 7000,
          'text': 'hello',
        });
        // Held: nothing new is shown, no second row.
        expect(await notes(), hasLength(1));
        expect(holds, hasLength(1));
        expect(holds.single.duration, MessageRepository.selfHold);
        expect(MessageRepository.selfHold, const Duration(seconds: 3));

        await ack(cid, 50, ts: 7000);
        final rows = await notes();
        expect(rows.single.msgId, '50');
        expect(rows.single.status, MessageStatus.sent);
        expect(holds.single.isCancelled, isTrue);
        fireHolds();
        await settle();
        expect(await notes(), hasLength(1));
      },
    );

    test(
      'ack, then message: the later copy is a duplicate and is ignored',
      () async {
        await write('hello');
        await ack(lastCid(), 50);
        await emit({
          'type': 'self_message',
          'id': 50,
          'ts': 1000,
          'text': 'hello',
        });
        expect(await notes(), hasLength(1));
        expect(holds, isEmpty);
      },
    );

    test(
      'the same text from another device is its own note: matching never uses text',
      () async {
        await write('same words');
        final cid = lastCid();
        // Another device wrote the same words; its copy arrives first.
        await emit({
          'type': 'self_message',
          'id': 70,
          'ts': 6000,
          'text': 'same words',
        });
        await ack(cid, 71, ts: 7000);
        // The held copy of the other device is added when the hold runs out.
        expect(await notes(), hasLength(1));
        fireHolds();
        await settle();
        expect((await notes()).map((m) => m.msgId), ['70', '71']);
      },
    );

    test(
      'a message from another device during a pending send is added after the hold',
      () async {
        await write('mine');
        final cid = lastCid();
        await emit({
          'type': 'self_message',
          'id': 51,
          'ts': 5000,
          'text': 'other phone',
        });
        expect(await notes(), hasLength(1));
        fireHolds();
        await settle();
        var rows = await notes();
        expect(rows.map((m) => m.text), ['other phone', 'mine']);
        await ack(cid, 52, ts: 6000);
        rows = await notes();
        expect(rows.map((m) => m.msgId), ['51', '52']);
        expect(rows.every((m) => m.status == MessageStatus.sent), isTrue);
      },
    );

    test('two pending notes: each echo finishes its own row', () async {
      await write('A');
      await write('B');
      expect(socket.sent, hasLength(1));
      final a = lastCid();
      await emit({'type': 'self_message', 'id': 61, 'ts': 100, 'text': 'A'});
      await ack(a, 61, ts: 100);
      expect(socket.sent, hasLength(2));
      final b = lastCid();
      expect(b, isNot(a));
      await emit({'type': 'self_message', 'id': 62, 'ts': 200, 'text': 'B'});
      await ack(b, 62, ts: 200);
      final rows = await notes();
      expect(rows.map((m) => m.msgId), ['61', '62']);
      expect(rows.map((m) => m.text), ['A', 'B']);
      expect(await count('outbox'), 0);
    });

    test('with no note in flight a message is added at once', () async {
      await emit({'type': 'self_message', 'id': 80, 'ts': 100, 'text': 'x'});
      expect(await notes(), hasLength(1));
      expect(holds, isEmpty);
    });

    test(
      'an ack for a client id this phone does not know changes nothing',
      () async {
        await write('hello');
        await ack('m-unknown', 99);
        final m = (await notes()).single;
        expect(m.isLocalTemp, isTrue);
        expect(await count('outbox'), 1);
      },
    );

    test(
      'ack lost: the repeat ack after reconnect finishes the row, history adds no second one',
      () async {
        await write('hello');
        final cid = lastCid();
        // the answer never arrived; the connection came back and history already has the note
        await reconnect([_item(50, 7000, text: 'hello')]);
        expect(
          socket.sent.where((l) => l.contains('/self hello')),
          hasLength(2),
        );
        await ack(cid, 50, isDuplicate: true, ts: 7000);
        final rows = await notes();
        expect(rows.map((m) => m.msgId), ['50']);
        expect(rows.single.status, MessageStatus.sent);
        expect(await count('outbox'), 0);
      },
    );

    test('a held copy is added, not lost, when the connection drops', () async {
      await write('mine');
      await emit({
        'type': 'self_message',
        'id': 51,
        'ts': 5000,
        'text': 'other',
      });
      expect(await notes(), hasLength(1));
      socket.connection.value = SocketState.offline;
      await settle();
      expect((await notes()).map((m) => m.msgId), contains('51'));
    });

    test(
      'a copy held for one organisation is never added to another',
      () async {
        await write('mine');
        await emit({
          'type': 'self_message',
          'id': 51,
          'ts': 5000,
          'text': 'other',
        });
        session.current.value = const SessionInfo(
          orgId: 'org2',
          userId: 'Ann',
          expiresTs: 1 << 50,
        );
        await settle();
        fireHolds();
        await settle();
        expect(await count('messages', "msg_id = '51'"), 0);
      },
    );
  });

  group('encryption', () {
    test(
      'required: an envelope with a box for each own device, this phone included',
      () async {
        useEncryption(devices: [phone.asPublic, other, third]);
        await write('secret');
        expect(socket.sent, hasLength(1));
        final env = envelopeOf(socket.sent.single);
        expect(env['conv'], 'self:ann');
        expect(env['dev'], phone.id);
        expect((env['keys'] as Map).keys.toSet(), {
          phone.id,
          other.id,
          third.id,
        });
        expect(socket.sent.single, isNot(contains('secret')));
        // The row keeps what was typed and shows the lock.
        final m = (await notes()).single;
        expect(m.text, 'secret');
        expect(m.isEncrypted, isTrue);
        await ack(lastCid(), 5);
        expect((await notes()).single.text, 'secret');
      },
    );

    test(
      'a person with ONE device works: the only box is this phone',
      () async {
        useEncryption(devices: [phone.asPublic]);
        await write('secret');
        final env = envelopeOf(socket.sent.single);
        expect((env['keys'] as Map).keys.toList(), [phone.id]);
      },
    );

    test('the recovery key gets a box like in a direct chat', () async {
      const recovery = E2eDevicePublic(
        id: 'rec',
        ecdh: 'x',
        sign: 'x',
        isRecovery: true,
      );
      final real = await crypto.generateDeviceKeys();
      final decision = EncryptionPolicy.decideSelf(
        mode: 'required',
        isEncryptedThread: false,
        myDevices: [phone.asPublic, real.asPublic, recovery],
        keys: phone,
        pinChanges: const [],
      );
      expect(decision.recipients.map((d) => d.id).toSet(), {
        phone.id,
        real.id,
        'rec',
      });
    });

    test(
      'keys not ready: the note waits as "Waiting for encryption", nothing is sent',
      () async {
        useEncryption(isReady: false);
        expect(await write('secret'), SendResult.queued);
        expect(socket.sent, isEmpty);
        var m = (await notes()).single;
        expect(m.status, MessageStatus.pending);
        expect(m.isWaitingForEncryption, isTrue);
        expect(await count('outbox', "status = 'pending'"), 1);

        // The phone gets its keys: the note goes out, encrypted, at once.
        e2e.deviceKeys = phone;
        e2e.isSetting = false;
        e2e.regs.add(null);
        await settle(300);
        expect(socket.sent, hasLength(1));
        expect(envelopeOf(socket.sent.single)['conv'], 'self:ann');
        m = (await notes()).single;
        expect(m.isWaitingForEncryption, isFalse);
        expect(m.status, MessageStatus.sending);
      },
    );

    test(
      'the device list cannot be read: the note waits, never plain',
      () async {
        useEncryption();
        e2e.devicesError = const SocketCallError('timeout');
        await write('secret');
        expect(socket.sent, isEmpty);
        expect((await notes()).single.isWaitingForEncryption, isTrue);
        e2e.devicesError = null;
        e2e.regs.add(null);
        await settle(300);
        expect(socket.sent, hasLength(1));
        expect(
          E2eCrypto.isEnvelope(socket.sent.single.split(' /self ').last),
          isTrue,
        );
      },
    );

    test('the mode is not known yet: the note waits, never plain', () async {
      useEncryption();
      socket.isModeDown = true;
      await write('secret');
      expect(socket.sent, isEmpty);
      expect((await notes()).single.isWaitingForEncryption, isTrue);
    });

    test(
      'e2e_stale_devices: the list is read again, a new envelope goes out under the same cid, once',
      () async {
        useEncryption(devices: [phone.asPublic, other]);
        await write('secret');
        final cid = lastCid();
        final first = envelopeOf(socket.sent.single);
        final calls = e2e.devicesCalls;

        // A third device appeared while the envelope was being written.
        e2e.devices = [phone.asPublic, other, third];
        await emit({
          'type': 'error',
          'code': 'e2e_stale_devices',
          'mid': first['mid'],
          'conv': 'self:ann',
          'users': ['ann'],
        });
        await settle(300);
        expect(e2e.invalidated, contains('ann'));
        expect(e2e.devicesCalls, greaterThan(calls));
        expect(socket.sent, hasLength(2));
        expect(cidOf(socket.sent.last), cid);
        final second = envelopeOf(socket.sent.last);
        expect(second['mid'], isNot(first['mid']));
        expect((second['keys'] as Map).keys.toSet(), {
          phone.id,
          other.id,
          third.id,
        });

        // Refused again: no third try, the note fails (never plain).
        await emit({
          'type': 'error',
          'code': 'e2e_stale_devices',
          'mid': second['mid'],
          'conv': 'self:ann',
          'users': ['ann'],
        });
        await settle(300);
        expect(socket.sent, hasLength(2));
        expect((await notes()).single.status, MessageStatus.failed);
      },
    );

    test(
      'a box the server refuses (bad_envelope) is refreshed and tried once more',
      () async {
        useEncryption(devices: [phone.asPublic, other]);
        await write('secret');
        await emit({'type': 'error', 'code': 'bad_envelope', 'text': 'box'});
        await settle(300);
        expect(socket.sent, hasLength(2));
        await emit({'type': 'error', 'code': 'bad_envelope', 'text': 'box'});
        await settle(300);
        expect(socket.sent, hasLength(2));
        expect((await notes()).single.status, MessageStatus.failed);
      },
    );

    test('a changed key of one of my devices blocks; nothing is sent', () async {
      useEncryption();
      e2e.pins = [E2ePinChange(user: 'ann', device: other)];
      // The composer reads only caches, so the refusal comes when it goes out.
      expect(await write('secret'), SendResult.queued);
      expect(socket.sent, isEmpty);
      final m = (await notes()).single;
      expect(m.status, MessageStatus.failed);
      expect(m.secureFailure, contains('security key changed'));
    });

    test('off: plain; optional with no device of mine: plain', () async {
      await write('plain one');
      expect(socket.sent.single, endsWith('/self plain one'));
      await ack(lastCid(), 1);

      useEncryption(mode: 'optional', devices: const []);
      e2e.deviceKeys = null;
      await write('plain two');
      expect(socket.sent.last, endsWith('/self plain two'));
    });

    test('optional with a device of mine: encrypted, like the web', () async {
      useEncryption(mode: 'optional', devices: [phone.asPublic]);
      await write('quiet');
      expect(socket.sent.last, isNot(contains('quiet')));
      expect(
        E2eCrypto.isEnvelope(socket.sent.last.split(' /self ').last),
        isTrue,
      );
    });
  });

  group('no plain note where encryption is required', () {
    final devices = <String, List<E2eDevicePublic> Function()>{
      'none': () => const [],
      'this phone': () => [phone.asPublic],
      'other only': () => [other],
      'both': () => [phone.asPublic, other],
    };

    test('the rule never answers plain in required mode, for any state', () {
      for (final hasKeys in [true, false]) {
        for (final isSettingUp in [true, false]) {
          for (final entry in devices.entries) {
            for (final pins in [
              const <E2ePinChange>[],
              [E2ePinChange(user: 'ann', device: other)],
            ]) {
              for (final isThread in [true, false]) {
                final d = EncryptionPolicy.decideSelf(
                  mode: 'required',
                  isEncryptedThread: isThread,
                  myDevices: entry.value(),
                  keys: hasKeys ? phone : null,
                  pinChanges: pins,
                  isSettingUp: isSettingUp,
                );
                expect(
                  d.verdict,
                  isNot(E2eSendVerdict.plain),
                  reason:
                      'keys=$hasKeys setting=$isSettingUp devices=${entry.key} '
                      'pins=${pins.length} thread=$isThread',
                );
                if (d.isEncrypt) {
                  expect(d.recipients.map((r) => r.id), contains(phone.id));
                }
              }
            }
          }
        }
      }
      // The mode not known yet is not plain either.
      expect(
        EncryptionPolicy.decideSelf(
          mode: null,
          isEncryptedThread: false,
          myDevices: const [],
          keys: null,
          pinChanges: const [],
        ).verdict,
        E2eSendVerdict.unknown,
      );
    });

    test(
      'through the policy and the outbox, no line leaves unencrypted in any state',
      () async {
        for (final name in devices.keys) {
          for (final hasKeys in [true, false]) {
            for (final fails in [true, false]) {
              useEncryption(devices: devices[name]!(), isReady: hasKeys);
              e2e.devicesError = fails
                  ? const SocketCallError('timeout')
                  : null;
              socket.isModeDown = false;
              socket.sent.clear();
              await db.update('DELETE FROM outbox');
              await db.update('DELETE FROM messages');
              await repo.sendText('self', 'plain words $name');
              await settle();
              await repo.flush();
              await settle();
              for (final line in socket.sent) {
                expect(
                  line,
                  isNot(contains('plain words')),
                  reason: 'devices=$name keys=$hasKeys fails=$fails',
                );
                expect(line, contains(' /self e2e1:'));
              }
            }
          }
        }
      },
    );

    test(
      'no wire line for a note is anything but /self, and none reaches the global room',
      () {
        OutboxEntry entry(String conv, String kind) => OutboxEntry(
          id: 1,
          convId: conv,
          kind: kind,
          payload: const {'text': 'words', 'replyTo': '3'},
          refId: 'temp-1',
          status: 'pending',
          retryCount: 0,
          nextAttemptTs: 0,
          createdTs: 0,
          cid: 'm-1',
        );
        expect(
          MessageRepository.wireCommand(entry('self', 'message')),
          '/c m-1 /self words',
        );
        // Reply, edit and delete have their own lines; anything else (and an id
        // that is not a server id) has none, never a fall-through to plain text.
        expect(
          MessageRepository.wireCommand(entry('self', 'reply')),
          '/c m-1 /replyself 3 words',
        );
        for (final kind in ['edit', 'delete', 'other']) {
          expect(MessageRepository.wireCommand(entry('self', kind)), isNull);
        }
        // The global room cannot carry a cid and is a different conversation.
        expect(
          MessageRepository.wireCommand(entry('global', 'message')),
          'words',
        );
        expect(SelfConversation.isSelf('global'), isFalse);
      },
    );
  });
}
