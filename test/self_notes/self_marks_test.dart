import 'dart:async';

import 'package:connectum/core/log/log_redaction.dart';
import 'package:connectum/data/db/app_database.dart';
import 'package:connectum/data/marks/mark_commands.dart';
import 'package:connectum/data/models/session_info.dart';
import 'package:connectum/data/repositories/marks_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/read_gate.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Session extends Fake implements SessionStore {
  @override
  final current = Rxn<SessionInfo>(
    const SessionInfo(orgId: 'org', userId: 'Ann', expiresTs: 1 << 50),
  );

  @override
  String? get orgId => current.value?.orgId;
  @override
  String? get userId => current.value?.userId;
  @override
  bool get hasSession => current.value != null;
}

class _Socket extends Fake implements SocketService {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  final calls = <({String action, Map<String, dynamic> args})>[];
  final answers = <String, Object>{};

  /// Held until completed: the answer of a command that is still on its way.
  Completer<void>? hold;

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
    if (!isOnline) throw const SocketCallError('not_connected');
    calls.add((action: action, args: args));
    final wait = hold;
    if (wait != null) await wait.future;
    final answer = answers[action];
    if (answer is SocketCallError) throw answer;
    if (answer is Map<String, dynamic>) return answer;
    return const {};
  }

  Iterable<String> get actions => calls.map((c) => c.action);
}

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
  late MarksRepository repo;
  late List<_HandTimer> timers;
  late List<String> notices;
  late DateTime clock;

  MarksRepository build() {
    final r = MarksRepository(
      db,
      session,
      socket,
      ReadGate(now: () => clock, delay: (d) async => clock = clock.add(d)),
      timer: (d, cb) {
        final t = _HandTimer(d, cb);
        timers.add(t);
        return t;
      },
    )..onInit();
    r.notices.listen(notices.add);
    return r;
  }

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
    socket = _Socket();
    timers = [];
    notices = [];
    clock = DateTime(2026, 11, 25);
    repo = build();
  });

  tearDown(() async {
    await socket.controller.close();
    await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
  });

  Future<void> settle([int ms = 40]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  /// Fires every timer that waits (a read delay or a retry).
  Future<void> fire() async {
    for (final t in timers.where((t) => t.isActive).toList()) {
      t.isFired = true;
      t.callback();
    }
    await settle();
  }

  Future<void> emit(Map<String, dynamic> e) async {
    socket.controller.add(e);
    await settle();
  }

  Future<void> addNote(int id, {bool isDeleted = false}) => db.insert(
    "INSERT INTO messages(org_id, user_id, msg_id, conv_id, sender, is_mine, kind, text, ts, status, is_deleted) "
    "VALUES('org','Ann',?,'self','Ann',1,'chat','note',?,'sent',?)",
    ['$id', id, isDeleted ? 1 : 0],
  );

  Future<int> count(String table) async {
    final rows = await db.query('SELECT COUNT(*) AS n FROM $table');
    return rows.first['n'] as int;
  }

  Map<String, dynamic> pins(List<Map<String, dynamic>> list) => {
    'pins': list,
    'max': 10,
  };

  Map<String, dynamic> pinItem(int id, {String text = 'hello', int ts = 5}) => {
    'id': id,
    'by': 'Ann',
    'ts': ts,
    'message': {'id': id, 'from': 'Ann', 'text': text, 'ts': 1, 'kind': 'chat'},
  };

  group('the commands and their shapes', () {
    test(
      'save, unsave, pin, unpin: the arguments the server expects',
      () async {
        await addNote(7);
        await repo.toggleSave('7');
        await settle();
        await repo.toggleSave('7');
        await settle();
        await repo.togglePin('7');
        await settle();
        await repo.unpin('7');
        await settle();
        expect(socket.calls.map((c) => '${c.action} ${c.args}'), [
          'msg.save {conv: self, id: 7}',
          'msg.unsave {id: 7}',
          'msg.pin {conv: self, id: 7}',
          'msg.unpin {conv: self, id: 7}',
        ]);
        expect(await count('message_marks'), 0);
      },
    );

    test(
      'the lists are read with msg.pins {conv} and msg.saved {ids:true}',
      () async {
        socket.answers[MarkCmd.pins] = pins([]);
        socket.answers[MarkCmd.saved] = {'ids': <int>[]};
        await repo.refreshPins();
        await repo.refreshSaved();
        expect(socket.calls.map((c) => '${c.action} ${c.args}'), [
          'msg.pins {conv: self}',
          'msg.saved {ids: true}',
        ]);
      },
    );
  });

  group('optimistic, queued, restored', () {
    test(
      'the change shows before the server answers and is confirmed after',
      () async {
        await addNote(7);
        socket.hold = Completer<void>();
        await repo.toggleSave('7');
        await settle();
        expect(repo.isSaved('7'), isTrue);
        expect(repo.marks['7']!.isWaiting, isTrue);
        socket.hold!.complete();
        await settle();
        expect(repo.isSaved('7'), isTrue);
        expect(repo.marks['7']!.isWaiting, isFalse);
        expect(repo.marks['7']!.isConfirmedSaved, isTrue);
      },
    );

    test(
      'offline: shown at once, nothing sent, sent once when online',
      () async {
        await addNote(7);
        socket.connection.value = SocketState.offline;
        await repo.toggleSave('7');
        await repo.togglePin('7');
        await settle();
        expect(repo.isSaved('7'), isTrue);
        expect(repo.isPinned('7'), isTrue);
        expect(repo.pinned.single.msgId, '7');
        expect(socket.calls, isEmpty);
        socket.connection.value = SocketState.online;
        await repo.flush();
        await settle();
        expect(socket.actions, [MarkCmd.save, MarkCmd.pin]);
        await repo.flush();
        expect(socket.calls, hasLength(2));
        expect(repo.marks['7']!.isWaiting, isFalse);
      },
    );

    test(
      'a wish survives a restart and is sent by the new repository',
      () async {
        await addNote(7);
        socket.connection.value = SocketState.offline;
        await repo.toggleSave('7');
        await repo.togglePin('7');
        await settle();
        final again = build();
        await again.load();
        expect(again.isSaved('7'), isTrue);
        expect(again.isPinned('7'), isTrue);
        socket.connection.value = SocketState.online;
        await again.flush();
        expect(socket.actions, [MarkCmd.save, MarkCmd.pin]);
      },
    );

    test('confirmed marks are read back from SQLite after a restart', () async {
      await addNote(7);
      await repo.toggleSave('7');
      await repo.togglePin('7');
      await settle();
      final again = build();
      await again.load();
      expect(again.marks['7']!.isConfirmedSaved, isTrue);
      expect(again.pinned.map((m) => m.msgId), ['7']);
    });

    test('a toggle and a toggle back before sending sends nothing', () async {
      await addNote(7);
      socket.connection.value = SocketState.offline;
      await repo.toggleSave('7');
      await repo.toggleSave('7');
      await settle();
      socket.connection.value = SocketState.online;
      await repo.flush();
      expect(socket.calls, isEmpty);
      expect(repo.marks, isEmpty);
      expect(await count('message_marks'), 0);
    });

    test('the pin limit: the pin goes back and the message says why', () async {
      await addNote(7);
      socket.answers[MarkCmd.pin] = const SocketCallError('limit', 'full');
      await repo.togglePin('7');
      await settle();
      expect(repo.isPinned('7'), isFalse);
      expect(repo.pinned, isEmpty);
      expect(notices, ['You can pin at most 10 notes. Unpin one first']);
      expect(await count('message_marks'), 0);
    });

    test('any other refusal restores and says it did not work', () async {
      await addNote(7);
      socket.answers[MarkCmd.save] = const SocketCallError('invalid', 'x');
      await repo.toggleSave('7');
      await settle();
      expect(repo.isSaved('7'), isFalse);
      expect(notices, [MarksRepository.couldNot]);
    });

    test('a refused unsave keeps the note saved', () async {
      await addNote(7);
      await repo.toggleSave('7');
      await settle();
      socket.answers[MarkCmd.unsave] = const SocketCallError('invalid', 'x');
      await repo.toggleSave('7');
      await settle();
      expect(repo.isSaved('7'), isTrue);
      expect(repo.marks['7']!.isWaiting, isFalse);
    });

    test(
      'a note the server does not know: marks dropped, short message',
      () async {
        await addNote(7);
        socket.answers[MarkCmd.pin] = const SocketCallError('not_found', 'x');
        await repo.togglePin('7');
        await settle();
        expect(repo.marks, isEmpty);
        expect(notices, [MarksRepository.noteGone]);
      },
    );

    test('a note with no server id is ignored', () async {
      await repo.toggleSave('temp-1');
      await repo.togglePin('');
      await settle();
      expect(socket.calls, isEmpty);
      expect(await count('message_marks'), 0);
    });

    test('a connection gap keeps the wish and retries by timer', () async {
      await addNote(7);
      socket.answers[MarkCmd.save] = const SocketCallError('timeout');
      await repo.toggleSave('7');
      await settle();
      expect(repo.isSaved('7'), isTrue);
      expect(repo.marks['7']!.isWaiting, isTrue);
      expect(notices, isEmpty);
      expect(timers.where((t) => t.isActive), isNotEmpty);
      socket.answers.remove(MarkCmd.save);
      await fire();
      expect(socket.calls, hasLength(2));
      expect(repo.marks['7']!.isConfirmedSaved, isTrue);
    });

    test('rate limited keeps the wish too', () async {
      await addNote(7);
      socket.answers[MarkCmd.pin] = const SocketCallError('rate_limited');
      await repo.togglePin('7');
      await settle();
      expect(repo.isPinned('7'), isTrue);
      expect(notices, isEmpty);
    });

    test(
      'saving twice on the server is safe: the answer is the same',
      () async {
        await addNote(7);
        socket.answers[MarkCmd.save] = {'saved': true};
        await repo.toggleSave('7');
        await settle();
        // Another device saved it too: the server's list names it, the wish is
        // gone, nothing is sent a second time.
        socket.answers[MarkCmd.saved] = {
          'ids': [7],
        };
        await repo.refreshSaved();
        expect(repo.isSaved('7'), isTrue);
        expect(socket.actions.where((a) => a == MarkCmd.save), hasLength(1));
      },
    );

    test(
      'an unsave of a note that is not saved is sent and harmless',
      () async {
        await addNote(7);
        socket.answers[MarkCmd.saved] = {
          'ids': [7],
        };
        await repo.refreshSaved();
        socket.answers[MarkCmd.saved] = {'ids': <int>[]};
        await repo.refreshSaved();
        expect(repo.isSaved('7'), isFalse);
      },
    );
  });

  group('reading, events and reconciling', () {
    test('pins_changed for self: a burst is one read', () async {
      socket.answers[MarkCmd.pins] = pins([]);
      for (var i = 0; i < 5; i++) {
        await emit({
          'type': 'sd_event',
          'event': 'pins_changed',
          'data': {'conv': 'self', 'id': i, 'pinned': true, 'by': 'Ann'},
        });
      }
      expect(socket.calls, isEmpty);
      await fire();
      expect(socket.actions.where((a) => a == MarkCmd.pins), hasLength(1));
      expect(repo.pinReads, 1);
    });

    test('pins_changed with deleted:true drops the pin, no read', () async {
      await addNote(7);
      await addNote(8);
      await repo.togglePin('7');
      await repo.togglePin('8');
      await repo.toggleSave('7');
      await fire();
      await fire();
      socket.calls.clear();
      final reads = repo.pinReads;
      await emit({
        'type': 'sd_event',
        'event': 'pins_changed',
        'data': {
          'conv': 'self',
          'id': 7,
          'pinned': false,
          'by': 'Ann',
          'deleted': true,
        },
      });
      await fire();
      expect(repo.pinned.map((m) => m.msgId), ['8']);
      expect(repo.marks.containsKey('7'), isFalse);
      expect(socket.calls, isEmpty);
      expect(repo.pinReads, reads);
      final again = build();
      await again.load();
      expect(again.pinned.map((m) => m.msgId), ['8']);
    });

    test(
      'pins_changed deleted for another conversation changes nothing',
      () async {
        await addNote(7);
        await repo.togglePin('7');
        await fire();
        await fire();
        socket.calls.clear();
        await emit({
          'type': 'sd_event',
          'event': 'pins_changed',
          'data': {'conv': 'dm:bob', 'id': 7, 'pinned': false, 'deleted': true},
        });
        await fire();
        expect(repo.pinned.map((m) => m.msgId), ['7']);
        expect(socket.calls, isEmpty);
      },
    );

    test('pins_changed of another conversation is not read', () async {
      await emit({
        'type': 'sd_event',
        'event': 'pins_changed',
        'data': {'conv': 'dm:bob', 'id': 1, 'pinned': true, 'by': 'bob'},
      });
      await fire();
      expect(socket.calls, isEmpty);
    });

    test(
      'the server list replaces what was confirmed; a waiting wish stays',
      () async {
        await addNote(1);
        await addNote(2);
        await addNote(3);
        socket.answers[MarkCmd.pins] = pins([pinItem(1, ts: 50)]);
        await repo.refreshPins();
        expect(repo.pinned.map((m) => m.msgId), ['1']);
        expect(repo.pinned.single.preview, 'hello');
        // A wish for 3 waits (offline); the server then lists 2 only.
        socket.connection.value = SocketState.offline;
        await repo.togglePin('3');
        socket.connection.value = SocketState.online;
        socket.answers[MarkCmd.pins] = pins([pinItem(2, ts: 60)]);
        socket.hold = Completer<void>()..complete();
        await repo.refreshPins();
        expect(repo.marks['1'], isNull);
        expect(repo.isPinned('2'), isTrue);
        expect(repo.isPinned('3'), isTrue);
        expect(repo.marks['3']!.isWaiting, isTrue);
        expect(repo.pinMax.value, 10);
      },
    );

    test('an envelope in a pin is not kept as text', () async {
      await addNote(1);
      socket.answers[MarkCmd.pins] = pins([pinItem(1, text: 'e2e1:abc')]);
      await repo.refreshPins();
      expect(repo.pinned.single.preview, isEmpty);
    });

    test('saved_changed from another device sets the marker', () async {
      await addNote(7);
      await emit({
        'type': 'sd_event',
        'event': 'saved_changed',
        'data': {'id': 7, 'saved': true},
      });
      expect(repo.isSaved('7'), isTrue);
      await emit({
        'type': 'sd_event',
        'event': 'saved_changed',
        'data': {'id': 7, 'saved': false},
      });
      expect(repo.isSaved('7'), isFalse);
      expect(await count('message_marks'), 0);
    });

    test('a list that is not the shape is ignored', () async {
      await addNote(7);
      await repo.toggleSave('7');
      await settle();
      socket.answers[MarkCmd.saved] = {'ids': 'nope'};
      socket.answers[MarkCmd.pins] = {'pins': 3};
      await repo.refreshSaved();
      await repo.refreshPins();
      expect(repo.isSaved('7'), isTrue);
    });

    test('a failed read keeps what is shown', () async {
      await addNote(7);
      await repo.toggleSave('7');
      await settle();
      socket.answers[MarkCmd.saved] = const SocketCallError('timeout');
      await repo.refreshSaved();
      expect(repo.isSaved('7'), isTrue);
    });
  });

  group('a deleted note', () {
    test('self_deleted drops its marks and its waiting wish', () async {
      await addNote(7);
      socket.connection.value = SocketState.offline;
      await repo.toggleSave('7');
      await repo.togglePin('7');
      await settle();
      socket.connection.value = SocketState.online;
      await emit({
        'type': 'sd_event',
        'event': 'self_deleted',
        'data': {'messageId': 7},
      });
      expect(repo.marks, isEmpty);
      expect(repo.pinned, isEmpty);
      expect(await count('message_marks'), 0);
      await repo.flush();
      expect(socket.calls, isEmpty);
    });

    test('a note deleted here is not shown and its wish is not sent', () async {
      await addNote(7);
      socket.connection.value = SocketState.offline;
      await repo.togglePin('7');
      await settle();
      await db.update("UPDATE messages SET is_deleted = 1 WHERE msg_id = '7'");
      await repo.load();
      expect(repo.pinned, isEmpty);
      socket.connection.value = SocketState.online;
      await repo.flush();
      expect(socket.calls, isEmpty);
    });

    test('the server naming a deleted note is ignored', () async {
      await addNote(7, isDeleted: true);
      await addNote(8);
      socket.answers[MarkCmd.pins] = pins([pinItem(7), pinItem(8)]);
      socket.answers[MarkCmd.saved] = {
        'ids': [7, 8],
      };
      await repo.refreshPins();
      await repo.refreshSaved();
      expect(repo.marks.keys, ['8']);
      await emit({
        'type': 'sd_event',
        'event': 'saved_changed',
        'data': {'id': 7, 'saved': true},
      });
      expect(repo.marks.keys, ['8']);
    });
  });

  group('scope', () {
    test('a sign out wipes the marks and the waiting wishes', () async {
      await addNote(7);
      socket.connection.value = SocketState.offline;
      await repo.toggleSave('7');
      await repo.togglePin('7');
      await settle();
      expect(AppDatabase.scopedTables, contains('message_marks'));
      expect(await count('message_marks'), 1);
      await db.wipeScope('org', 'Ann');
      expect(await count('message_marks'), 0);
      await repo.load();
      expect(repo.marks, isEmpty);
      expect(repo.pinned, isEmpty);
    });

    test('another organisation never sees these rows', () async {
      await addNote(7);
      await repo.toggleSave('7');
      await settle();
      session.current.value = const SessionInfo(
        orgId: 'other',
        userId: 'Ann',
        expiresTs: 1 << 50,
      );
      await repo.load();
      expect(repo.marks, isEmpty);
    });

    test('nothing is sent with no session', () async {
      await addNote(7);
      session.current.value = null;
      await repo.toggleSave('7');
      await repo.flush();
      expect(socket.calls, isEmpty);
    });
  });

  test('the pins reply is logged with the note text masked', () {
    final body = LogRedaction.body(MarkCmd.pins, {
      'pins': [
        {
          'id': 7,
          'message': {'id': 7, 'text': 'my secret plan'},
        },
      ],
    });
    expect(body, isNot(contains('my secret plan')));
  });
}
