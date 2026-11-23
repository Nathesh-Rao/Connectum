import 'dart:async';

import 'package:connectum/core/crash/crash_service.dart';
import 'package:connectum/data/db/app_database.dart';
import 'package:connectum/data/models/session_info.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/e2e_repository.dart';
import 'package:connectum/data/repositories/encryption_policy.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../crash/fake_crash_reporter.dart';

class _Db extends Fake implements AppDatabase {
  @override
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?>? a]) =>
      Future.error(StateError('db broke'));
}

class _Session extends Fake implements SessionStore {
  @override
  final current = Rxn<SessionInfo>();
  @override
  String? get orgId => 'org';
  @override
  String? get userId => 'ann';
}

class _Socket extends Fake implements SocketService {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  bool isCurrent(Map<String, dynamic> event) => true;
  @override
  final connection = SocketState.online.obs;
  @override
  StreamSubscription<void> listenOnline(
    String name,
    FutureOr<void> Function() run,
  ) => const Stream<void>.empty().listen((_) {});
}

class _E2e extends Fake implements E2eRepository {
  @override
  Stream<void> get unlockRequests => const Stream.empty();
  @override
  Stream<void> get registrations => const Stream.empty();
}

class _Conversations extends Fake implements ConversationRepository {
  @override
  Stream<String> get receiptsChanged => const Stream.empty();
}

class _Policy extends Fake implements EncryptionPolicy {}

void main() {
  late FakeCrashReporter reporter;
  late CrashService oldService;
  late DebugPrintCallback oldPrint;
  late List<String> logs;

  setUp(() {
    oldService = CrashService.current;
    reporter = FakeCrashReporter();
    CrashService.current = CrashService(reporter);
    logs = [];
    oldPrint = debugPrint;
    debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
  });

  tearDown(() {
    debugPrint = oldPrint;
    CrashService.current = oldService;
  });

  test('a failing decrypt pass and event are logged and reported', () async {
    final socket = _Socket();
    final repo = MessageRepository(
      _Db(),
      _Session(),
      socket,
      _Conversations(),
      _Policy(),
      _E2e(),
    );
    repo.onInit();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      logs.any((l) => l.contains('decrypt pass')),
      isTrue,
      reason: '$logs',
    );

    socket.controller.add({'type': 'dm_ack', 'with': 'bob', 'cid': 'm-1'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(logs.any((l) => l.contains('message event')), isTrue);
    expect(reporter.nonFatals, isNotEmpty);
    expect(reporter.reasons, containsAll(['decrypt pass']));
  });

  test('the queue keeps going after a failed event', () async {
    final socket = _Socket();
    MessageRepository(
      _Db(),
      _Session(),
      socket,
      _Conversations(),
      _Policy(),
      _E2e(),
    ).onInit();
    socket.controller.add({'type': 'dm_ack', 'with': 'a', 'cid': 'm-1'});
    socket.controller.add({'type': 'dm_ack', 'with': 'b', 'cid': 'm-2'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(logs.where((l) => l.contains('message event')).length, 2);
  });
}
