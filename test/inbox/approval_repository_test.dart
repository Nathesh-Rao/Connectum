import 'package:connectum/data/repositories/approval_repository.dart';
import 'package:connectum/data/repositories/feed_repository.dart';
import 'package:connectum/data/socket/read_gate.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import 'inbox_support.dart';

Map<String, dynamic> raw(
  int id, {
  String status = 'pending',
  bool canRespond = true,
  String direction = 'incoming',
}) => {
  'id': id,
  'type': 'submission',
  'status': status,
  'from': 'rhea',
  'approvers': ['meg'],
  'direction': direction,
  'canRespond': canRespond,
  'createdTs': 1000 + id,
};

Map<String, dynamic> page(
  List<Map<String, dynamic>> rows, {
  bool more = false,
}) => {'requests': rows, 'total': rows.length, 'hasMore': more};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GateClock clock;
  late HeldSocket socket;
  late ApprovalRepository repo;
  late FeedRepository feed;

  setUp(() {
    clock = GateClock();
    socket = HeldSocket()..goOnline();
    final store = FakeStore(user: 'meg');
    feed = FeedRepository(socket, store, FakeE2e())..onInit();
    repo = ApprovalRepository(
      socket,
      store,
      feed,
      gate: ReadGate(now: clock.read, delay: clock.delay),
    )..onInit();
    socket.handler = (action, args) async {
      if (action == 'req.list') return page([raw(1), raw(2)]);
      return <String, dynamic>{};
    };
  });

  tearDown(() {
    repo.onClose();
    feed.onClose();
  });

  test(
    'the count is pending and canRespond; what I sent is never counted',
    () async {
      socket.handler = (action, args) async => page([
        raw(1),
        raw(2),
        raw(3, canRespond: false, direction: 'outgoing'),
        raw(4, status: 'accepted', canRespond: false),
      ]);
      await repo.start();
      expect(repo.count.value, 2);
      expect(repo.all, hasLength(4));
      expect(repo.hasRead.value, isTrue);
    },
  );

  test('the first read asks for every status with a limit', () async {
    await repo.start();
    expect(socket.calls.single.action, 'req.list');
    expect(socket.calls.single.args, {'status': 'all', 'limit': 200});
  });

  test('pages with offset while hasMore, one at a time, at most 5', () async {
    var open = 0;
    var most = 0;
    socket.handler = (action, args) async {
      open++;
      most = open > most ? open : most;
      await Future<void>.delayed(Duration.zero);
      open--;
      final offset = (args['offset'] as int?) ?? 0;
      return page([
        for (var i = 0; i < 200; i++) raw(offset + i + 1),
      ], more: true);
    };
    await repo.refresh();
    final offsets = [
      for (final c in socket.calls) (c.args['offset'] as int?) ?? 0,
    ];
    expect(offsets, [0, 200, 400, 600, 800]);
    expect(most, 1);
    expect(repo.all, hasLength(1000));
  });

  test('it stops at the first page without hasMore', () async {
    socket.handler = (action, args) async {
      final offset = (args['offset'] as int?) ?? 0;
      return offset == 0 ? page([raw(1), raw(2)], more: true) : page([raw(3)]);
    };
    await repo.refresh();
    expect(socket.calls, hasLength(2));
    expect([for (final a in repo.all) a.id], [1, 2, 3]);
  });

  test('every read goes through the shared gate', () async {
    final gate = ReadGate(now: clock.read, delay: clock.delay);
    final r = ApprovalRepository(
      socket,
      FakeStore(user: 'meg'),
      feed,
      gate: gate,
    )..onInit();
    await r.refresh();
    await r.refresh();
    expect(gate.sent, 2);
    r.onClose();
  });

  test('a late answer never overwrites a newer fact', () async {
    await repo.start();
    expect(repo.count.value, 2);
    final held = socket.handler;
    socket.handler = null;
    final read = repo.refresh();
    await settle();
    expect(socket.waiting, hasLength(1));
    repo.onEvent({
      'type': 'sd_event',
      'event': 'request_resolved',
      'data': {
        'request': {...raw(1), 'status': 'accepted'},
      },
    });
    expect(repo.count.value, 1);
    socket.waiting.single.done.complete(page([raw(1), raw(2)]));
    expect(await read, isFalse);
    expect(repo.count.value, 1);
    expect(repo.all.firstWhere((a) => a.id == 1).status, 'accepted');
    socket.handler = held;
  });

  test('request_created adds one waiting for me and counts it', () async {
    await repo.start();
    repo.onEvent({
      'type': 'sd_event',
      'event': 'request_created',
      'data': {
        'request': {
          'id': 9,
          'type': 'associate',
          'from': 'zed',
          'approvers': ['meg'],
          'status': 'pending',
        },
      },
    });
    expect(repo.count.value, 3);
    expect(repo.all.first.id, 9);
  });

  test('a failed read keeps the list and says so', () async {
    await repo.start();
    socket.handler = (a, b) async => throw const SocketCallError('timeout');
    expect(await repo.refresh(), isFalse);
    expect(repo.hasError.value, isTrue);
    expect(repo.isOfflineError.value, isTrue);
    expect(repo.all, hasLength(2));
    expect(repo.count.value, 2);
  });

  test('my own answer updates the list at once', () async {
    await repo.start();
    socket.handler = (action, args) async => action == 'req.respond'
        ? {
            'request': {...raw(1), 'status': 'accepted', 'canRespond': false},
          }
        : page([raw(1), raw(2)]);
    await repo.respond(1, 'accept');
    expect(repo.count.value, 1);
    expect(socket.calls.last.args, {'id': 1, 'action': 'accept'});
  });

  test('reset forgets the last session', () async {
    await repo.start();
    repo.reset();
    expect(repo.all, isEmpty);
    expect(repo.count.value, 0);
    expect(repo.hasRead.value, isFalse);
  });
}
