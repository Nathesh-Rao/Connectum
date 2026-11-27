import 'dart:async';
import 'dart:convert';

import 'package:connectum/data/db/app_database.dart';
import 'package:connectum/data/e2e/e2e_crypto.dart';
import 'package:connectum/data/e2e/e2e_key_store.dart';
import 'package:connectum/data/e2e/e2e_models.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/core/selection/selection_rules.dart';
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
  E2eReading reading = const E2eReading.pending();
  Map<String, List<E2eDevicePublic>> members = {};
  final invalidatedGroups = <String>[];

  @override
  Map<String, List<E2eDevicePublic>>? cachedGroupDevices(String group) =>
      members.isEmpty ? null : members;
  @override
  Future<Map<String, List<E2eDevicePublic>>> groupDevices(String group) async =>
      members;
  @override
  void invalidateGroup(String group) => invalidatedGroups.add(group);

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

  Future<int> count(String table, [String where = '1=1']) async {
    final rows = await db.query(
      'SELECT COUNT(*) AS n FROM $table WHERE $where',
    );
    return rows.first['n'] as int;
  }

  void useEncryption({String mode = 'required'}) {
    socket.mode = mode;
    e2e.devices = [phone.asPublic, other];
    e2e.members = {
      'ann': [phone.asPublic],
      'bob': [other],
    };
    e2e.deviceKeys = phone;
    policy.onReconnected();
  }

  /// A message of mine the server has, [ago] old, in [conv].
  Future<void> seed(
    String conv,
    int id,
    String text, {
    Duration ago = const Duration(minutes: 1),
    bool isMine = true,
    String status = 'sent',
    String kind = 'chat',
    bool isDeleted = false,
    bool isEnc = false,
  }) async {
    await db.transaction((sql) async {
      await ConversationRepository.ensure(sql, 'org', 'Ann', conv);
      await sql.insert(
        'INSERT INTO messages(org_id, user_id, msg_id, conv_id, sender, is_mine, kind, text, ts, status, is_deleted, '
        'is_encrypted_unsupported, decrypt_state, plaintext) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          'org',
          'Ann',
          '$id',
          conv,
          isMine ? 'Ann' : 'Bob',
          isMine ? 1 : 0,
          kind,
          isEnc ? 'e2e1:{}' : text,
          repo.clock() - ago.inMilliseconds,
          status,
          isDeleted ? 1 : 0,
          isEnc ? 1 : 0,
          isEnc ? 'ok' : null,
          isEnc ? text : null,
        ],
      );
    });
  }

  Future<Message> msg(String conv, int id) async => (await repo.readFor(
    'org',
    'Ann',
    conv,
  )).firstWhere((m) => m.msgId == '$id');

  Map<String, dynamic> envelopeOf(String line) {
    final text = line.split(' ').skip(4).join(' ');
    expect(
      E2eCrypto.isEnvelope(text),
      isTrue,
      reason: 'not an envelope: $line',
    );
    return jsonDecode(text.substring(E2eCrypto.prefix.length))
        as Map<String, dynamic>;
  }

  Future<bool> canEdit(String conv, int id) async =>
      repo.canEditChat(await msg(conv, id));

  group('Edit shown: own sendable text message inside 15 minutes', () {
    for (final conv in ['dm:bob', 'group:team']) {
      test('plain $conv', () async {
        await seed(conv, 1, 'hello', ago: const Duration(minutes: 14));
        expect(await canEdit(conv, 1), isTrue);
        final target = SelectionTarget(
          id: '1',
          canEdit: await canEdit(conv, 1),
        );
        expect(SelectionRules.available([target]), [SelectionAction.edit]);
      });
      test('encrypted $conv', () async {
        await seed(conv, 2, 'secret', isEnc: true);
        expect(await canEdit(conv, 2), isTrue);
      });
    }
  });

  group('Edit hidden', () {
    test(
      'other people, old, pending, failed, deleted, files, forms, notes',
      () async {
        await seed('dm:bob', 1, 'theirs', isMine: false);
        expect(await canEdit('dm:bob', 1), isFalse);
        await seed('dm:bob', 2, 'old', ago: const Duration(minutes: 16));
        expect(await canEdit('dm:bob', 2), isFalse);
        await seed('dm:bob', 3, 'pending', status: 'pending');
        expect(await canEdit('dm:bob', 3), isFalse);
        await seed('dm:bob', 4, 'failed', status: 'failed');
        expect(await canEdit('dm:bob', 4), isFalse);
        await seed('dm:bob', 5, 'gone', isDeleted: true);
        expect(await canEdit('dm:bob', 5), isFalse);
        await seed(
          'dm:bob',
          6,
          '[ATTACHMENT:{"kind":"image","name":"a.png","url":"/uploads/a.png","type":"image/png","size":"1 KB"}]',
        );
        expect(await canEdit('dm:bob', 6), isFalse);
        await seed('dm:bob', 7, 'form', kind: 'form');
        expect(await canEdit('dm:bob', 7), isFalse);
      },
    );

    test('the window follows the server clock from the last history', () async {
      await seed('dm:bob', 1, 'x', ago: const Duration(minutes: 14));
      expect(await canEdit('dm:bob', 1), isTrue);
      // The server's clock is 2 minutes ahead of the phone: 16 minutes there.
      socket.history['/history dm bob'] = {
        'scope': 'dm',
        'with': 'bob',
        'now': repo.clock() + const Duration(minutes: 2).inMilliseconds,
        'list': <Map<String, dynamic>>[],
      };
      await repo.open('dm:bob');
      await repo.syncNow();
      await settle();
      expect(await canEdit('dm:bob', 1), isFalse);
    });
  });

  group('plain edit', () {
    test(
      'queued: new text at once with a clock, no cid, echo settles it',
      () async {
        await seed('dm:bob', 10, 'first');
        expect(await repo.editText('10', 'second'), isTrue);
        await settle();
        expect(socket.sent.last, '/edit dm bob 10 second');
        var m = await msg('dm:bob', 10);
        expect(m.text, 'second');
        expect(m.isEditPending, isTrue);
        await emit({
          'type': 'dm_edited',
          'messageId': 10,
          'text': 'second',
          'editedTs': 5000,
          'userA': 'ann',
          'userB': 'bob',
        });
        m = await msg('dm:bob', 10);
        expect(m.text, 'second');
        expect(m.isEditPending, isFalse);
        expect(m.editedTs, 5000);
        expect(await count('outbox'), 0);
      },
    );

    test('too old locally: refused with "Too old to edit"', () async {
      await seed('group:team', 11, 'a', ago: const Duration(minutes: 20));
      final notices = <String>[];
      repo.notices.listen(notices.add);
      expect(await repo.editText('11', 'b'), isFalse);
      await settle();
      expect(notices, ['Too old to edit']);
      expect(await count('outbox'), 0);
    });

    test(
      'expired from the server: dropped, old text back, never retried',
      () async {
        await seed('group:team', 12, 'before');
        final notices = <String>[];
        repo.notices.listen(notices.add);
        await repo.editText('12', 'after');
        await settle();
        expect(socket.sent.last, '/edit group team 12 after');
        await emit({
          'type': 'edit_denied',
          'messageId': 12,
          'reason': 'expired',
        });
        final m = await msg('group:team', 12);
        expect(m.text, 'before');
        expect(m.isEditPending, isFalse);
        expect(await count('outbox'), 0);
        expect(notices, ['Too old to edit']);
        final before = socket.sent.length;
        await repo.flush();
        await settle();
        expect(socket.sent, hasLength(before));
      },
    );

    test('deleted removes the message', () async {
      await seed('dm:bob', 13, 'x');
      await repo.editText('13', 'y');
      await settle();
      await emit({'type': 'edit_denied', 'messageId': 13, 'reason': 'deleted'});
      expect((await msg('dm:bob', 13)).isDeleted, isTrue);
      expect(await count('outbox'), 0);
    });

    test('forbidden restores the text and says so', () async {
      await seed('dm:bob', 14, 'a');
      final notices = <String>[];
      repo.notices.listen(notices.add);
      await repo.editText('14', 'b');
      await settle();
      await emit({
        'type': 'edit_denied',
        'messageId': 14,
        'reason': 'forbidden',
      });
      expect((await msg('dm:bob', 14)).text, 'a');
      expect(notices, [MessageRepository.couldNotEditMessage]);
    });
  });

  group('encrypted edit', () {
    for (final conv in ['dm:bob', 'group:team']) {
      test(
        '$conv: envelope for every device, mine included, never plain',
        () async {
          useEncryption();
          await seed(conv, 20, 'old text', isEnc: true);
          expect(await repo.editText('20', 'new text'), isTrue);
          await settle();
          final line = socket.sent.single;
          expect(
            line,
            startsWith(
              conv == 'dm:bob'
                  ? '/edit dm bob 20 e2e1:'
                  : '/edit group team 20 e2e1:',
            ),
          );
          expect(line, isNot(contains('new text')));
          expect(line, isNot(startsWith('/c ')));
          final boxes = (envelopeOf(line)['keys'] as Map).keys.toSet();
          expect(boxes, {phone.id, other.id});
          final m = await msg(conv, 20);
          expect(m.text, 'new text');
          expect(m.isEditPending, isTrue);
        },
      );
    }

    test(
      'stale devices: lists refreshed, sealed again once, then drops',
      () async {
        useEncryption();
        await seed('dm:bob', 21, 'old', isEnc: true);
        await repo.editText('21', 'new');
        await settle();
        final first = socket.sent.single;
        final mid = E2eCrypto.midOf(first.split(' ').last);
        e2e.devices = [phone.asPublic, other, third];
        await emit({
          'type': 'error',
          'code': 'e2e_stale_devices',
          'mid': mid,
          'conv': 'dm:bob',
          'users': ['bob'],
        });
        await settle();
        expect(socket.sent, hasLength(2));
        expect(socket.sent.last, isNot(first));
        expect((envelopeOf(socket.sent.last)['keys'] as Map).keys.toSet(), {
          phone.id,
          other.id,
          third.id,
        });
        expect(e2e.invalidated, contains('bob'));
        // A second refusal is final: the old text returns, nothing goes plain.
        await emit({
          'type': 'error',
          'code': 'e2e_stale_devices',
          'mid': E2eCrypto.midOf(socket.sent.last.split(' ').last),
          'conv': 'dm:bob',
          'users': ['bob'],
        });
        await settle();
        expect(socket.sent, hasLength(2));
        expect((await msg('dm:bob', 21)).text, 'old');
        expect(await count('outbox'), 0);
        expect(socket.sent.where((l) => l.contains('new')), isEmpty);
      },
    );

    test('bad_envelope: devices read again, one more try', () async {
      useEncryption();
      await seed('group:team', 22, 'old', isEnc: true);
      await repo.editText('22', 'new');
      await settle();
      await emit({'type': 'error', 'code': 'bad_envelope'});
      await settle();
      expect(socket.sent, hasLength(2));
      expect(e2e.invalidatedGroups, ['team']);
    });

    test('a changed security key blocks it: old text, nothing sent', () async {
      useEncryption();
      e2e.pins = [E2ePinChange(user: 'bob', device: other)];
      await seed('dm:bob', 23, 'old', isEnc: true);
      final notices = <String>[];
      repo.notices.listen(notices.add);
      await repo.editText('23', 'new');
      await settle();
      expect(socket.sent, isEmpty);
      expect((await msg('dm:bob', 23)).text, 'old');
      expect(await count('outbox'), 0);
      expect(notices, hasLength(1));
    });

    test('expired and deleted answers', () async {
      useEncryption();
      await seed('dm:bob', 24, 'old', isEnc: true);
      final notices = <String>[];
      repo.notices.listen(notices.add);
      await repo.editText('24', 'new');
      await settle();
      await emit({'type': 'edit_denied', 'messageId': 24, 'reason': 'expired'});
      var m = await msg('dm:bob', 24);
      expect(m.text, 'old');
      expect(m.isEncrypted, isTrue);
      expect(notices, ['Too old to edit']);
      await repo.editText('24', 'again');
      await settle();
      await emit({'type': 'edit_denied', 'messageId': 24, 'reason': 'deleted'});
      m = await msg('dm:bob', 24);
      expect(m.isDeleted, isTrue);
    });

    test('a # line is never sent into an encrypted chat', () async {
      useEncryption();
      await seed('dm:bob', 25, 'old', isEnc: true);
      expect(await repo.editText('25', '#help'), isFalse);
      expect(socket.sent, isEmpty);
    });

    test('encryption not ready: dropped, never plain', () async {
      useEncryption(mode: 'optional');
      e2e.deviceKeys = phone;
      socket.mode = 'off';
      policy.onReconnected();
      await seed('dm:bob', 26, 'old', isEnc: true);
      await repo.editText('26', 'new');
      await settle();
      expect(socket.sent.where((l) => l.contains('new')), isEmpty);
      expect((await msg('dm:bob', 26)).text, 'old');
    });

    test('our own echo settles by mid and does not flicker', () async {
      useEncryption();
      await seed('dm:bob', 27, 'old', isEnc: true);
      await repo.editText('27', 'new');
      await settle();
      final envelope = socket.sent.single.split(' ').last;
      await emit({
        'type': 'dm_edited',
        'messageId': 27,
        'text': envelope,
        'editedTs': 9000,
        'userA': 'ann',
        'userB': 'bob',
      });
      var m = await msg('dm:bob', 27);
      expect(m.text, 'new');
      expect(m.decryptState, 'ok');
      expect(m.isEditPending, isFalse);
      expect(m.editedTs, 9000);
      // The same event again changes nothing (still readable, still new).
      await emit({
        'type': 'dm_edited',
        'messageId': 27,
        'text': 'e2e1:{"trimmed":true}',
        'editedTs': 9000,
        'userA': 'ann',
        'userB': 'bob',
      });
      m = await msg('dm:bob', 27);
      expect(m.text, 'new');
      expect(m.decryptState, 'ok');
    });
  });

  group('receive', () {
    for (final isGroup in [false, true]) {
      test(
        '${isGroup ? 'group' : 'dm'}: an encrypted edit opens with the marker',
        () async {
          final conv = isGroup ? 'group:team' : 'dm:bob';
          await seed(conv, 30, 'before', isMine: false, isEnc: true);
          e2e.reading = const E2eReading.ok('after');
          await emit({
            'type': isGroup ? 'group_edited' : 'dm_edited',
            'messageId': 30,
            'text': 'e2e1:{"v":1}',
            'editedTs': 7000,
            if (isGroup)
              'group': 'team'
            else ...{
              'userA': 'bob',
              'userB': 'ann',
            },
          });
          await settle();
          final m = await msg(conv, 30);
          expect(m.text, 'after');
          expect(m.editedTs, 7000);
        },
      );
    }

    test('one this phone cannot open shows as locked', () async {
      await seed('dm:bob', 31, 'before', isMine: false, isEnc: true);
      e2e.reading = const E2eReading.cannot('no_box');
      await emit({
        'type': 'dm_edited',
        'messageId': 31,
        'text': 'e2e1:{"v":1}',
        'editedTs': 7000,
        'userA': 'bob',
        'userB': 'ann',
      });
      await settle();
      final m = await msg('dm:bob', 31);
      expect(m.decryptState, 'cant_decrypt');
      expect(m.isEncryptedUnsupported, isTrue);
      expect(m.editedTs, 7000);
    });

    test('a plain edit from someone else shows with the marker', () async {
      await seed('dm:bob', 32, 'before', isMine: false);
      await emit({
        'type': 'dm_edited',
        'messageId': 32,
        'text': 'after',
        'editedTs': 6000,
        'userA': 'bob',
        'userB': 'ann',
      });
      final m = await msg('dm:bob', 32);
      expect(m.text, 'after');
      expect(m.editedTs, 6000);
    });
  });
}
