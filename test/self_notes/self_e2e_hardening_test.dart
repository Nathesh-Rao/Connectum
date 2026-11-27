import 'dart:async';
import 'dart:convert';

import 'package:connectum/data/db/app_database.dart';
import 'package:connectum/data/e2e/e2e_crypto.dart';
import 'package:connectum/data/e2e/e2e_key_store.dart';
import 'package:connectum/data/e2e/e2e_models.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/models/session_info.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/e2e_repository.dart';
import 'package:connectum/data/repositories/encryption_policy.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter/widgets.dart';
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
  final unlocks = StreamController<void>.broadcast();
  Map<String, List<E2eDevicePublic>> others = {};
  Duration? lastMaxAge;
  bool isOpening = false;
  int openCalls = 0;
  int sealPad = 0;
  int unlocked = -1;
  final signKeys = <String, String>{};

  @override
  Stream<void> get unlockRequests => unlocks.stream;
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
    lastMaxAge = maxAge;
    final error = devicesError;
    if (error != null) throw error;
    return {
      for (final u in users)
        u.toLowerCase(): others[u.toLowerCase()] ?? devices,
    };
  }

  @override
  Future<List<E2ePinChange>> checkPins(
    Map<String, List<E2eDevicePublic>> byUser, {
    required bool isRecord,
  }) async => pins;
  @override
  void invalidate(Iterable<String> users) => invalidated.addAll(users);
  @override
  Future<String> seal(
    E2eSendDecision decision,
    String convId,
    String text,
  ) async {
    final env = await real.seal(decision, convId, text);
    return sealPad == 0 ? env : env + ' ' * sealPad;
  }

  @override
  Future<void> finishUnlock({required int readable}) async =>
      unlocked = readable;
  @override
  Future<E2eReading> open({
    required String text,
    required String convId,
    String? expectConv,
    E2eDeviceKeys? keys,
    Future<String?> Function(String user, String deviceId)? signKeyFor,
    Future<E2eDevicePublic?> Function(String user, String deviceId)? deviceFor,
    Map<String, ({String ecdh, String sign})>? testPins,
  }) async {
    openCalls++;
    if (deviceKeys == null) return const E2eReading.cannot('no_device');
    return !isOpening
        ? const E2eReading.pending()
        : real.open(
            text: text,
            convId: convId,
            keys: deviceKeys,
            signKeyFor: (user, id) async => signKeys[id],
          );
  }
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
  late E2eDeviceKeys otherKeys;
  late E2eDeviceKeys bobKeys;

  final crypto = E2eCrypto();

  setUpAll(() async {
    phone = await crypto.generateDeviceKeys();
    otherKeys = await crypto.generateDeviceKeys();
    other = otherKeys.asPublic;
    bobKeys = await crypto.generateDeviceKeys();
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

  Future<String> sealAs(
    E2eDeviceKeys from,
    List<E2eDevicePublic> to,
    String text, {
    String conv = 'self:ann',
    String user = 'ann',
  }) => crypto.buildEnvelope(
    user: user,
    keys: from,
    conv: conv,
    recipients: to,
    text: text,
  );

  /// What the other device (the browser in the backend test) makes of it.
  Future<String> openAs(
    E2eDeviceKeys device,
    String envelope, {
    String conv = 'self:ann',
  }) async {
    try {
      final opened = await crypto.openEnvelope(
        text: envelope,
        keys: device,
        signKeyFor: (user, id) async => {
          phone.id: phone.signPub,
          otherKeys.id: otherKeys.signPub,
          bobKeys.id: bobKeys.signPub,
        }[id],
        expectConv: conv,
      );
      return opened.text;
    } on E2eException catch (e) {
      return 'ERR:${e.code}';
    }
  }

  void openForReal() {
    e2e.isOpening = true;
    e2e.signKeys[phone.id] = phone.signPub;
    e2e.signKeys[otherKeys.id] = otherKeys.signPub;
    e2e.signKeys[bobKeys.id] = bobKeys.signPub;
  }

  Map<String, dynamic> envItem(
    int id,
    String envelope, {
    int ts = 1000,
    bool isE2e = true,
  }) => {..._item(id, ts, text: envelope), 'e2e': isE2e};

  Future<Message> only() async => (await notes()).single;

  String wireText(String line) =>
      line.replaceFirst(RegExp(r'^/c \S+ /self '), '');

  group('backend scenarios ported (connectum_selfmsg_e2e_test.mjs)', () {
    test(
      'BE1 two devices: both read the note, the wire never holds the words',
      () async {
        useEncryption(devices: [phone.asPublic, otherKeys.asPublic]);
        await write('my private note');
        final env = wireText(socket.sent.single);
        expect(env, startsWith('e2e1:'));
        expect(env, isNot(contains('my private note')));
        expect(await openAs(phone, env), 'my private note');
        expect(await openAs(otherKeys, env), 'my private note');
      },
    );

    test(
      'BE2 the history carries the envelope and this device opens it',
      () async {
        openForReal();
        e2e.deviceKeys = phone;
        final env = await sealAs(phone, [
          phone.asPublic,
          other,
        ], 'my private note');
        await reconnect([envItem(3, env)]);
        await settle(300);
        final m = await only();
        expect(m.text, 'my private note');
        expect(m.decryptState, 'ok');
        expect(m.isEncryptedUnsupported, isFalse);
      },
    );

    test(
      'BE3 the sending device always has its own box, with the other device',
      () async {
        useEncryption(devices: [phone.asPublic, other]);
        await write('n');
        final boxes = (envelopeOf(socket.sent.single)['keys'] as Map).keys
            .toSet();
        expect(boxes, {phone.id, other.id});
      },
    );

    test(
      'BE4 a device left out (list was stale): refused once, new envelope has its box',
      () async {
        useEncryption(devices: [phone.asPublic]);
        await write('n');
        final first = envelopeOf(socket.sent.single);
        expect((first['keys'] as Map).keys.toSet(), {phone.id});
        e2e.devices = [phone.asPublic, other];
        await emit({
          'type': 'error',
          'code': 'e2e_stale_devices',
          'mid': first['mid'],
          'conv': 'self:ann',
          'users': ['ann'],
        });
        await settle(300);
        expect(socket.sent, hasLength(2));
        expect((envelopeOf(socket.sent.last)['keys'] as Map).keys.toSet(), {
          phone.id,
          other.id,
        });
        expect(await count('outbox'), 1);
      },
    );

    test('BE5 a box for somebody else is never made', () async {
      useEncryption(devices: [phone.asPublic, other]);
      e2e.others = {
        'bob': [bobKeys.asPublic],
      };
      await write('n');
      final boxes = (envelopeOf(socket.sent.single)['keys'] as Map).keys
          .toSet();
      expect(boxes, isNot(contains(bobKeys.id)));
      expect(boxes, {phone.id, other.id});
    });

    test(
      'BE6 an envelope made for a direct chat is not shown in the notes',
      () async {
        openForReal();
        e2e.deviceKeys = phone;
        final env = await sealAs(
          phone,
          [phone.asPublic],
          'x',
          conv: 'dm:ann:bob',
        );
        expect(await openAs(phone, env), 'ERR:wrong_conversation');
        await reconnect([envItem(4, env)]);
        await settle(300);
        final m = await only();
        expect(m.isEncryptedUnsupported, isTrue);
        expect(m.unreadableCode, 'wrong_conversation');
      },
    );

    test(
      "BE7 an envelope for someone else's own conversation is not shown",
      () async {
        openForReal();
        e2e.deviceKeys = phone;
        final env = await sealAs(
          phone,
          [phone.asPublic],
          'x',
          conv: 'self:bob',
        );
        await reconnect([envItem(4, env)]);
        await settle(300);
        expect((await only()).unreadableCode, 'wrong_conversation');
      },
    );

    test('BE8 a damaged envelope stays a locked row, never a crash', () async {
      openForReal();
      e2e.deviceKeys = phone;
      await reconnect([envItem(5, 'e2e1:this is not an envelope')]);
      await settle(300);
      final m = await only();
      expect(m.decryptState, 'cant_decrypt');
      expect(m.isEncryptedUnsupported, isTrue);
    });

    test(
      "BE9 another person's envelope planted in my notes is hidden",
      () async {
        openForReal();
        e2e.deviceKeys = phone;
        final env = await sealAs(
          bobKeys,
          [phone.asPublic],
          'planted',
          user: 'bob',
        );
        await reconnect([envItem(6, env)]);
        await settle(300);
        final m = await only();
        expect(m.decryptState, 'cant_decrypt');
        expect(m.text, isNot('planted'));
        expect(m.unreadableCode, 'wrong_conversation');
      },
    );

    test(
      'BE10 a plain note is allowed where the organisation allows it (optional)',
      () async {
        useEncryption(mode: 'optional', devices: const []);
        e2e.deviceKeys = null;
        await write('a plain note');
        expect(socket.sent.single, endsWith('/self a plain note'));
      },
    );

    test(
      'BE11 an encrypted edit stays encrypted, and never goes out plain',
      () async {
        openForReal();
        useEncryption(devices: [phone.asPublic, other]);
        e2e.isOpening = true;
        final env = await sealAs(phone, [phone.asPublic, other], 'first');
        await reconnect([envItem(8, env)]);
        await settle(300);
        expect(await repo.editText('8', 'second'), isTrue);
        await settle(300);
        final line = socket.sent.last;
        expect(line, startsWith('/edit self 8 e2e1:'));
        expect(line, isNot(contains('second')));
        expect(
          await openAs(otherKeys, line.replaceFirst('/edit self 8 ', '')),
          'second',
        );

        // The organisation switches encryption off: the edit of an encrypted
        // note is dropped, nothing is sent in the clear.
        await emit({
          'type': 'self_edited',
          'messageId': 8,
          'text': line.replaceFirst('/edit self 8 ', ''),
          'editedTs': 9,
        });
        final before = socket.sent.length;
        socket.mode = 'off';
        policy.onReconnected();
        await repo.editText('8', 'third');
        await settle(300);
        expect(socket.sent.length, before);
        expect(socket.sent.any((l) => l.contains('third')), isFalse);
        expect(await count('outbox'), 0);
      },
    );

    test(
      'BE12 a device added later opens the old notes after the sync, no refresh',
      () async {
        openForReal();
        e2e.deviceKeys = phone;
        final oldEnv = await sealAs(otherKeys, [other], 'my private note');
        await reconnect([envItem(2, oldEnv)]);
        await settle(300);
        var m = await only();
        expect(m.unreadableCode, 'not_for_this_device');
        expect(await openAs(phone, oldEnv), 'ERR:not_for_this_device');

        // An older device hands the past on: the same note now has a box for
        // this phone. The unlock request fetches the history again.
        final handed = await sealAs(otherKeys, [
          other,
          phone.asPublic,
        ], 'my private note');
        socket.history['/history self'] = {
          'scope': 'self',
          'now': 0,
          'list': [envItem(2, handed)],
        };
        e2e.unlocks.add(null);
        await settle(600);
        m = await only();
        expect(m.text, 'my private note');
        expect(m.decryptState, 'ok');
        expect(e2e.unlocked, 1);
      },
    );

    test(
      'BE13 a removed or revoked device gets no box on the next note',
      () async {
        useEncryption(devices: [phone.asPublic, other, third]);
        await write('one');
        await ack(lastCid(), 1);
        expect(
          (envelopeOf(socket.sent.last)['keys'] as Map).keys,
          contains(third.id),
        );
        e2e.devices = [phone.asPublic, other];
        await emit({'type': 'e2e_devices'});
        policy.onReconnected();
        await write('two');
        expect((envelopeOf(socket.sent.last)['keys'] as Map).keys.toSet(), {
          phone.id,
          other.id,
        });
      },
    );

    test('BE14 the recovery key gets a box on the wire', () async {
      final recovery = E2eDevicePublic(
        id: third.id,
        ecdh: third.ecdh,
        sign: third.sign,
        isRecovery: true,
      );
      useEncryption(devices: [phone.asPublic, recovery]);
      await write('n');
      expect((envelopeOf(socket.sent.single)['keys'] as Map).keys.toSet(), {
        phone.id,
        third.id,
      });
    });
  });

  group('limits', () {
    test('11 devices: refused before sending, with a clear reason', () async {
      final many = <E2eDevicePublic>[
        phone.asPublic,
        for (var i = 0; i < 10; i++)
          E2eDevicePublic(id: 'd$i', ecdh: other.ecdh, sign: other.sign),
      ];
      useEncryption(devices: many);
      await write('n');
      expect(socket.sent, isEmpty);
      final m = await only();
      expect(m.status, MessageStatus.failed);
      expect(m.secureFailure, contains('more than 10 devices'));
    });

    test('10 devices still work', () async {
      useEncryption(
        devices: [
          phone.asPublic,
          for (var i = 0; i < 9; i++)
            E2eDevicePublic(id: 'd$i', ecdh: other.ecdh, sign: other.sign),
        ],
      );
      await write('n');
      expect(socket.sent, hasLength(1));
    });

    test('251 boxes: refused before sending', () {
      final decision = EncryptionPolicy.decideSelf(
        mode: 'required',
        isEncryptedThread: false,
        myDevices: [
          phone.asPublic,
          for (var i = 0; i < 250; i++)
            E2eDevicePublic(id: 'r$i', ecdh: 'x', sign: 'x', isRecovery: true),
        ],
        keys: phone,
        pinChanges: const [],
      );
      expect(decision.isBlocked, isTrue);
      expect(decision.message, contains('too many devices'));
      expect(decision.isEncrypt, isFalse);
    });

    test('250 boxes are allowed', () {
      final decision = EncryptionPolicy.decideSelf(
        mode: 'required',
        isEncryptedThread: false,
        myDevices: [
          phone.asPublic,
          for (var i = 0; i < 249; i++)
            E2eDevicePublic(id: 'r$i', ecdh: 'x', sign: 'x', isRecovery: true),
        ],
        keys: phone,
        pinChanges: const [],
      );
      expect(decision.isEncrypt, isTrue);
    });

    test('an envelope over 120000 characters is refused, never cut', () async {
      useEncryption();
      e2e.sealPad = 130000;
      await write('n');
      expect(socket.sent, isEmpty);
      final m = await only();
      expect(m.status, MessageStatus.failed);
      expect(m.secureFailure, contains('too large'));
    });

    test('2000 characters go, 2001 do not (send and edit)', () async {
      useEncryption();
      expect(await repo.sendText('self', 'a' * 2000), SendResult.queued);
      expect(await repo.sendText('self', 'a' * 2001), SendResult.tooLong);
      await settle();
      await emit({
        'type': 'self_message',
        'id': 30,
        'ts': 5,
        'from': 'Ann',
        'text': 'old',
      });
      expect(await repo.editText('30', 'a' * 2001), isFalse);
    });
  });

  group('new device and old notes', () {
    test(
      'a single device with no backup keeps the placeholder, never crashes',
      () async {
        openForReal();
        e2e.deviceKeys = phone;
        final oldEnv = await sealAs(otherKeys, [other], 'old');
        await reconnect([envItem(2, oldEnv)]);
        await settle(300);
        for (var i = 0; i < 3; i++) {
          e2e.unlocks.add(null);
          await settle(300);
        }
        final m = await only();
        expect(m.unreadableCode, 'not_for_this_device');
        expect(m.text, oldEnv);
        expect(await count('messages', "conv_id = 'self'"), 1);
      },
    );

    test(
      'a note locked because keys were not ready opens after the next sync',
      () async {
        openForReal();
        e2e.deviceKeys = null;
        final env = await sealAs(phone, [phone.asPublic], 'later');
        await reconnect([envItem(2, env)]);
        await settle(300);
        expect((await only()).unreadableCode, 'no_device');
        e2e.deviceKeys = phone;
        await reconnect([envItem(2, env)]);
        await settle(300);
        expect((await only()).text, 'later');
      },
    );
  });

  group('sending robustness', () {
    test('a changed key refuses up front, nothing is sent', () async {
      useEncryption();
      e2e.pins = [E2ePinChange(user: 'ann', device: other)];
      final gate = await repo.sendGate('self', isLookup: true);
      expect(gate.isKeyChange, isTrue);
      await write('n');
      expect(socket.sent, isEmpty);
      expect((await only()).secureFailure, contains('security key changed'));
    });

    test(
      'the device list is asked fresh (the chat rule) right before a send',
      () async {
        useEncryption();
        await write('n');
        expect(e2e.lastMaxAge, E2eRepository.sendListTtl);
      },
    );
  });

  group('waiting for encryption', () {
    final events = <String, Future<void> Function()>{
      'device registered': () async => e2e.regs.add(null),
      'sync done': () async => e2e.unlocks.add(null),
      'reconnect': () async => reconnect(),
      'app resume': () async =>
          repo.didChangeAppLifecycleState(AppLifecycleState.resumed),
    };
    for (final item in events.entries) {
      test(
        '${item.key} sends the waiting note at once, not after a poll',
        () async {
          useEncryption(isReady: false);
          await write('secret');
          expect(socket.sent, isEmpty);
          final wait = await db.query(
            'SELECT next_attempt_ts AS t FROM outbox',
          );
          final left =
              (wait.single['t'] as int) - DateTime.now().millisecondsSinceEpoch;
          expect(
            left,
            greaterThan(20000),
            reason: 'no 15 second poll any more',
          );
          e2e.deviceKeys = phone;
          e2e.isSetting = false;
          await item.value();
          await settle(400);
          final sent = socket.sent.where((l) => l.contains(' /self ')).toList();
          expect(sent, hasLength(1));
          expect(envelopeOf(sent.single)['conv'], 'self:ann');
        },
      );
    }

    test(
      'after 2 minutes the note asks for setup, stays queued, never plain',
      () async {
        useEncryption(isReady: false);
        await write('secret');
        final start = DateTime.now().millisecondsSinceEpoch;
        repo.clock = () => start + 3 * 60 * 1000;
        e2e.regs.add(null);
        await settle(300);
        var m = await only();
        expect(m.status, MessageStatus.pending);
        expect(m.isWaitingForEncryption, isTrue);
        expect(m.isSetupNeeded, isTrue);
        expect(await count('outbox', "status = 'pending'"), 1);
        expect(socket.sent, isEmpty);

        e2e.deviceKeys = phone;
        e2e.isSetting = false;
        e2e.regs.add(null);
        await settle(300);
        expect(socket.sent, hasLength(1));
        expect(socket.sent.single, isNot(contains('secret')));
        m = await only();
        expect(m.isSetupNeeded, isFalse);
      },
    );

    test(
      'a note never reaches the global room or a plain line while it waits',
      () async {
        useEncryption(isReady: false);
        await write('secret');
        repo.clock = () =>
            DateTime.now().millisecondsSinceEpoch + 10 * 60 * 1000;
        for (var i = 0; i < 3; i++) {
          e2e.regs.add(null);
          await settle(200);
        }
        expect(socket.sent, isEmpty);
      },
    );

    test('the 23 hour stop still applies to a waiting note', () async {
      useEncryption(isReady: false);
      await write('secret');
      await db.update('UPDATE outbox SET created_ts = ?', [
        DateTime.now().millisecondsSinceEpoch - 24 * 3600 * 1000,
      ]);
      e2e.regs.add(null);
      await settle(300);
      final m = await only();
      expect(m.status, MessageStatus.failed);
      expect(m.isTooOld, isTrue);
      expect(socket.sent, isEmpty);
    });
  });

  group('lost ack', () {
    test(
      'an encrypted note comes back as self_message: matched by mid, no second row',
      () async {
        useEncryption(devices: [phone.asPublic, other]);
        await write('secret');
        final env = wireText(socket.sent.single);
        await emit({
          'type': 'self_message',
          'id': 9,
          'ts': 2000,
          'from': 'Ann',
          'text': env,
        });
        expect(
          holds.where((h) => h.isActive),
          isEmpty,
          reason: 'no hold needed',
        );
        final m = await only();
        expect(m.msgId, '9');
        expect(m.text, 'secret');
        expect(m.status, MessageStatus.sent);
        expect(await count('outbox'), 0);
        // The late (duplicate) ack changes nothing.
        await ack(lastCid(), 9, isDuplicate: true);
        expect((await notes()), hasLength(1));
      },
    );

    test(
      'an encrypted note comes back in history: matched by mid, no duplicate',
      () async {
        useEncryption(devices: [phone.asPublic, other]);
        await write('secret');
        final env = wireText(socket.sent.single);
        await reconnect([envItem(9, env, ts: 2000)]);
        await settle(300);
        final rows = await notes();
        expect(rows, hasLength(1));
        expect(rows.single.msgId, '9');
        expect(rows.single.text, 'secret');
        expect(await count('outbox'), 0);
      },
    );

    test(
      'a first envelope matches after a stale re-seal (every mid is kept)',
      () async {
        useEncryption(devices: [phone.asPublic, other]);
        await write('secret');
        final first = wireText(socket.sent.single);
        final mid = envelopeOf(socket.sent.single)['mid'];
        e2e.devices = [phone.asPublic, other, third];
        await emit({
          'type': 'error',
          'code': 'e2e_stale_devices',
          'mid': mid,
          'conv': 'self:ann',
          'users': ['ann'],
        });
        await settle(300);
        expect(socket.sent, hasLength(2));
        await emit({
          'type': 'self_message',
          'id': 11,
          'ts': 2000,
          'from': 'Ann',
          'text': first,
        });
        expect(await notes(), hasLength(1));
        expect((await only()).msgId, '11');
      },
    );

    test(
      'a plain note with a lost ack falls back to the hold, matched by id only',
      () async {
        await write('hello');
        await emit({
          'type': 'self_message',
          'id': 9,
          'ts': 2000,
          'from': 'Ann',
          'text': 'hello',
        });
        // Held: the same text is never taken for the pending note.
        expect(holds.where((h) => h.isActive), isNotEmpty);
        expect(await notes(), hasLength(1));
        fireHolds();
        await settle(300);
        expect(await notes(), hasLength(2));
      },
    );
  });

  group('mixed notes and mode changes', () {
    test(
      'plain and encrypted notes show together; a plain note is never opened or locked',
      () async {
        openForReal();
        e2e.deviceKeys = phone;
        final env = await sealAs(phone, [phone.asPublic], 'sealed one');
        await reconnect([
          envItem(1, 'plain one', isE2e: false),
          envItem(2, env),
        ]);
        await settle(300);
        final rows = await notes();
        expect(rows, hasLength(2));
        final plain = rows.firstWhere((m) => m.msgId == '1');
        final sealed = rows.firstWhere((m) => m.msgId == '2');
        expect(plain.text, 'plain one');
        expect(plain.isEncrypted, isFalse);
        expect(plain.isEncryptedUnsupported, isFalse);
        expect(plain.decryptState, isNull);
        expect(sealed.text, 'sealed one');
        expect(e2e.openCalls, 1, reason: 'only the envelope was opened');
      },
    );

    test(
      'the organisation switches mode: new notes follow, old ones stay',
      () async {
        await write('before');
        await ack(lastCid(), 1);
        expect(socket.sent.last, endsWith('/self before'));
        useEncryption(devices: [phone.asPublic, other]);
        await write('after');
        expect(wireText(socket.sent.last), startsWith('e2e1:'));
        final rows = await notes();
        expect(rows.map((m) => m.text), containsAll(['before', 'after']));
        expect(rows.firstWhere((m) => m.text == 'before').isEncrypted, isFalse);
      },
    );

    test(
      'editing a plain note once the organisation requires encryption sends an envelope (as the web)',
      () async {
        await reconnect([envItem(5, 'old plain', isE2e: false)]);
        await settle(300);
        useEncryption(devices: [phone.asPublic, other]);
        expect(await repo.editText('5', 'new text'), isTrue);
        await settle(300);
        final line = socket.sent.last;
        expect(line, startsWith('/edit self 5 e2e1:'));
        expect(line, isNot(contains('new text')));
        expect(
          await openAs(otherKeys, line.replaceFirst('/edit self 5 ', '')),
          'new text',
        );
      },
    );
  });
}
