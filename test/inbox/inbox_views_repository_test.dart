import 'dart:async';

import 'package:connectum/data/repositories/inbox_views_repository.dart';
import 'package:connectum/data/socket/read_gate.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/inbox/models/inbox_saved_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import 'inbox_support.dart';

Map<String, dynamic> doc(List<String> names, {String? def}) => {
  'views': [
    for (final n in names)
      {
        'name': n,
        'view': {'folder': 'data'},
        'savedTs': 1,
      },
  ],
  'default': def,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GateClock clock;
  late HeldSocket socket;
  late FakeStore store;
  late InboxViewsRepository repo;

  setUp(() {
    clock = GateClock();
    socket = HeldSocket()..goOnline();
    store = FakeStore(user: 'ana');
    repo = InboxViewsRepository(
      socket,
      store,
      ReadGate(now: clock.read, delay: clock.delay),
    )..onInit();
  });

  List<String> asked() => [for (final c in socket.calls) c.action];

  test('get reads the views and the default', () async {
    socket.handler = (a, args) async => doc(['A', 'B'], def: 'B');
    final list = (await repo.load())!;
    expect(asked(), ['inbox.views.get']);
    expect(list.views.map((v) => v.name), ['A', 'B']);
    expect(repo.defaultName.value, 'B');
    expect(repo.isReady.value, isTrue);
  });

  test(
    'save reads the list first and checks against that fresh list',
    () async {
      // The phone knows two views; another device made the list full.
      socket.handler = (a, args) async => doc(['A', 'B']);
      await repo.load();
      socket.calls.clear();
      socket.handler = (a, args) async => a == 'inbox.views.get'
          ? doc([for (var i = 0; i < 20; i++) 'V$i'])
          : doc([]);
      await expectLater(
        repo.save('Fresh', {'folder': 'data'}, isNew: true),
        throwsA(
          isA<InboxViewError>().having(
            (e) => e.message,
            'message',
            InboxViewRules.tooMany,
          ),
        ),
      );
      expect(asked(), ['inbox.views.get'], reason: 'no save went out');

      // a name another device took meanwhile
      socket.calls.clear();
      socket.handler = (a, args) async => doc(['A', 'Taken']);
      await expectLater(
        repo.save('taken', {'folder': 'data'}, isNew: true),
        throwsA(isA<InboxViewError>()),
      );
    },
  );

  test(
    'save sends name and view after the get, and takes the answer',
    () async {
      socket.handler = (a, args) async =>
          a == 'inbox.views.get' ? doc(['A']) : doc(['A', 'New']);
      final list = await repo.save('New', {'folder': 'data'}, isNew: true);
      expect(asked(), ['inbox.views.get', 'inbox.views.save']);
      expect(socket.calls.last.args, {
        'name': 'New',
        'view': {'folder': 'data'},
      });
      expect(list.views.map((v) => v.name), ['A', 'New']);
      expect(repo.views.map((v) => v.name), ['A', 'New']);
    },
  );

  test('saving the default sends default:true', () async {
    socket.handler = (a, args) async =>
        doc(['Default View'], def: 'Default View');
    await repo.save('Default View', {'folder': 'data'}, isDefault: true);
    expect(socket.calls.last.action, 'inbox.views.save');
    expect(socket.calls.last.args['default'], isTrue);
    expect(repo.defaultName.value, 'Default View');
  });

  test(
    'the default is cleared with inbox.views.default and a null name',
    () async {
      socket.handler = (a, args) async => doc(['A']);
      await repo.setDefault(null);
      expect(socket.calls.single.action, 'inbox.views.default');
      expect(socket.calls.single.args, {'name': null});
      expect(repo.defaultName.value, isNull);
      await repo.setDefault('A');
      expect(socket.calls.last.args, {'name': 'A'});
    },
  );

  test(
    'delete reads the list first; a view that is gone is not deleted again',
    () async {
      socket.handler = (a, args) async =>
          a == 'inbox.views.get' ? doc(['A', 'B']) : doc(['A']);
      await repo.delete('B');
      expect(asked(), ['inbox.views.get', 'inbox.views.delete']);
      expect(socket.calls.last.args, {'name': 'B'});
      expect(repo.views.map((v) => v.name), ['A']);
      socket.calls.clear();
      socket.handler = (a, args) async => doc(['A']);
      await repo.delete('B');
      expect(asked(), ['inbox.views.get']);
    },
  );

  test("the server's own message is surfaced", () async {
    socket.handler = (a, args) async {
      if (a == 'inbox.views.get') return doc([]);
      throw const SocketCallError('invalid', 'The view is too big.');
    };
    await expectLater(
      repo.save('X', {'folder': 'data'}),
      throwsA(
        isA<SocketCallError>().having(
          (e) => e.message,
          'message',
          'The view is too big.',
        ),
      ),
    );
    expect(
      InboxViewsRepository.messageOf(
        const SocketCallError('invalid', 'The view is too big.'),
        'fallback',
      ),
      'The view is too big.',
    );
    expect(
      InboxViewsRepository.messageOf(const SocketCallError('x'), 'fallback'),
      'fallback',
    );
  });

  test('a late answer of an older get never wins', () async {
    // The gate sends one read at a time: the older answer lands first and is
    // dropped because a newer get was asked; the newer answer is the list.
    final first = Completer<Map<String, dynamic>>();
    final second = Completer<Map<String, dynamic>>();
    final answers = [first, second];
    socket.handler = (a, args) => answers.removeAt(0).future;
    final a = repo.load();
    await settle();
    final b = repo.load();
    await settle();
    first.complete(doc(['Old']));
    expect(await a, isNull);
    expect(repo.views, isEmpty, reason: 'the old answer was not taken');
    second.complete(doc(['New']));
    expect((await b)!.views.single.name, 'New');
    expect(repo.views.single.name, 'New');
  });

  test('a failed get keeps the last list and raises the error flag', () async {
    socket.handler = (a, args) async => doc(['A']);
    await repo.load();
    socket.handler = (a, args) async => throw const SocketCallError('timeout');
    await expectLater(repo.load(), throwsA(isA<SocketCallError>()));
    expect(repo.hasError.value, isTrue);
    expect(repo.views.single.name, 'A');
  });

  test('offline: nothing is sent', () async {
    socket.goOffline();
    await expectLater(repo.load(), throwsA(isA<SocketCallError>()));
    expect(socket.calls, isEmpty);
  });

  test('views from the web (odd shapes) never throw', () async {
    socket.handler = (a, args) async => {
      'views': [
        {
          'name': 'W',
          'view': {'kinds': 5, 'lens': []},
        },
        null,
        {'name': 5, 'view': {}},
      ],
      'default': 'W',
    };
    final list = (await repo.load())!;
    expect(list.views.single.name, 'W');
  });

  test('another person: the list is dropped', () async {
    socket.handler = (a, args) async => doc(['A']);
    await repo.load();
    repo.reset();
    expect(repo.views, isEmpty);
    expect(repo.isReady.value, isFalse);
  });
}
