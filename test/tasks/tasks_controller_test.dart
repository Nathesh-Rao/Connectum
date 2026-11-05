import 'dart:async';

import 'package:connectum/data/repositories/task_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/chats/models/chat_person.dart';
import 'package:connectum/features/tasks/tasks_controller.dart';
import 'package:connectum/features/tickets/tickets_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

Map<String, dynamic> _task(
  int id, {
  String status = 'open',
  String creator = 'me',
  String assignee = 'me',
}) => {
  'id': id,
  'title': 'Task $id',
  'description': '',
  'creator': creator,
  'assignee': assignee,
  'status': status,
  'priority': 'normal',
  'created': 1000 + id,
  'updated': 1000 + id,
  'due': null,
};

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late TaskRepository repo;
  late TasksController c;

  setUp(() async {
    socket = FakeSocket()..goOnline();
    final store = FakeStore(user: 'me');
    repo = TaskRepository(socket, store)..onInit();
    final tickets = TicketsController(
      tickets: TicketRepository(socket, store, FakeConversations()),
      connectivity: FakeConnectivity(),
    );
    socket.answers['task.list'] = <String, dynamic>{
      'tasks': [_task(1), _task(2, creator: 'ben')],
      'total': 2,
      'hasMore': false,
    };
    c = TasksController(
      tasks: repo,
      people: FakeGroups(),
      connectivity: FakeConnectivity(),
      tickets: tickets,
    )..onInit();
    await _settle();
  });

  tearDown(() {
    c.onClose();
    repo.onClose();
  });

  Map<String, dynamic> lastArgs(String action) =>
      socket.calls.lastWhere((x) => x.action == action).args;

  group('reading', () {
    test('both tabs are read with the right params', () {
      final reads = socket.calls.where((x) => x.action == 'task.list').toList();
      expect(reads.map((r) => r.args['as']).toSet(), {'assigned', 'created'});
      expect(reads.first.args['status'], 'active');
      expect(reads.first.args['limit'], 50);
      expect(reads.first.args.containsKey('offset'), isFalse);
    });

    test('Show more continues at the rows already held', () async {
      socket.answers['task.list'] = <String, dynamic>{
        'tasks': List.generate(50, (i) => _task(100 + i)),
        'hasMore': true,
      };
      await c.load('assigned');
      expect(c.lists['assigned']!.hasMore.value, isTrue);
      socket.answers['task.list'] = <String, dynamic>{
        'tasks': [_task(300)],
        'hasMore': false,
      };
      await c.loadMore('assigned');
      expect(lastArgs('task.list')['offset'], 50);
      expect(c.lists['assigned']!.items, hasLength(51));
      expect(c.lists['assigned']!.hasMore.value, isFalse);
    });

    test('changing the filter reads again with the new status', () async {
      c.selectFilter(1);
      await _settle();
      expect(lastArgs('task.list')['status'], 'done');
    });

    test('a failed first read is an error, never a stuck spinner', () async {
      socket.answers['task.list'] = const SocketCallError('timeout');
      c.selectFilter(2);
      await _settle();
      expect(c.lists['assigned']!.viewState.value.name, 'error');
    });
  });

  group('writes are sent once and never replayed', () {
    test(
      'create for myself leaves assignee out; for someone sends it',
      () async {
        socket.answers['task.create'] = <String, dynamic>{'task': _task(9)};
        expect(await c.newForm().onSubmit({'title': 'Mine'}), isTrue);
        expect(lastArgs('task.create'), {'title': 'Mine'});
        await c.newForm().onSubmit({'title': 'His', 'assignee': 'ben'});
        expect(lastArgs('task.create')['assignee'], 'ben');
        expect(socket.count('task.create'), 2);
      },
    );

    test('no cid and no request id in task.create', () async {
      socket.answers['task.create'] = <String, dynamic>{'task': _task(9)};
      await c.newForm().onSubmit({'title': 'Mine'});
      final args = lastArgs('task.create');
      expect(args.containsKey('cid'), isFalse);
      expect(args.containsKey('requestId'), isFalse);
    });

    test('a lost answer is not sent again; the lists are read again', () async {
      socket.answers['task.create'] = const SocketCallError('timeout');
      final reads = socket.count('task.list');
      expect(await c.newForm().onSubmit({'title': 'Once'}), isFalse);
      await _settle();
      expect(socket.count('task.create'), 1);
      expect(socket.count('task.list'), greaterThan(reads));
      expect(c.isBusy.value, isFalse);
    });

    test('offline: nothing is sent', () async {
      socket.goOffline();
      expect(await c.newForm().onSubmit({'title': 'x'}), isFalse);
      expect(socket.count('task.create'), 0);
      expect(c.isBusy.value, isFalse);
    });

    test('rate_limited: false, one call, nothing re-read', () async {
      socket.answers['task.create'] = const SocketCallError(
        'rate_limited',
        'Too many tasks this hour; try later.',
      );
      final reads = socket.count('task.list');
      expect(await c.newForm().onSubmit({'title': 'x'}), isFalse);
      await _settle();
      expect(socket.count('task.create'), 1);
      expect(socket.count('task.list'), reads);
    });

    test('a double tap on create is one call', () async {
      final gate = Completer<void>();
      socket.held['task.create'] = gate.future;
      socket.answers['task.create'] = <String, dynamic>{'task': _task(9)};
      final form = c.newForm();
      final a = form.onSubmit({'title': 'x'});
      final b = form.onSubmit({'title': 'x'});
      gate.complete();
      expect(await b, isFalse);
      expect(await a, isTrue);
      expect(socket.count('task.create'), 1);
    });

    test('status change: the row changes in place', () async {
      final t = c.find(1)!;
      socket.answers['task.update'] = <String, dynamic>{
        'task': _task(1, status: 'in_progress'),
      };
      expect(await c.start(t), isTrue);
      expect(lastArgs('task.update'), {'id': 1, 'status': 'in_progress'});
      expect(c.find(1)!.status, 'in_progress');
    });

    test('forbidden: the task is read again with task.get', () async {
      socket.answers['task.update'] = const SocketCallError(
        'forbidden',
        'Only the person who created the task can cancel it.',
      );
      socket.answers['task.get'] = <String, dynamic>{
        'task': _task(1, status: 'done'),
      };
      expect(await c.cancel(c.find(1)!), isFalse);
      await _settle();
      expect(lastArgs('task.get'), {'id': 1});
      expect(c.find(1)!.status, 'done');
    });

    test('not_found: the row is removed', () async {
      socket.answers['task.update'] = const SocketCallError(
        'not_found',
        'No such task.',
      );
      await c.complete(c.find(1)!);
      await _settle();
      expect(c.find(1), isNull);
    });

    test('send to someone else uses task.send {id, to}', () async {
      socket.answers['task.send'] = <String, dynamic>{
        'task': _task(1, assignee: 'ben'),
      };
      final ben = const ChatPerson(
        username: 'ben',
        name: 'Ben',
        source: 'colleague',
      );
      expect(await c.sendTo(c.find(1)!, ben), isTrue);
      expect(lastArgs('task.send'), {'id': 1, 'to': 'ben'});
    });
  });

  group('events', () {
    test('a task event reads both lists once, after 150 ms', () async {
      final reads = socket.count('task.list');
      repo.onEvent({
        'type': 'sd_event',
        'event': 'task_assigned',
        'data': {'task': _task(5, assignee: 'me', creator: 'ben')},
      });
      repo.onEvent({
        'type': 'sd_event',
        'event': 'task_updated',
        'data': {'task': _task(5, assignee: 'me', creator: 'ben')},
      });
      await _settle();
      expect(c.find(5), isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(socket.count('task.list'), reads + 2);
    });

    test('other events are ignored', () async {
      final reads = socket.count('task.list');
      repo.onEvent({'type': 'sd_event', 'event': 'feed_item', 'data': {}});
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(socket.count('task.list'), reads);
    });
  });
}
