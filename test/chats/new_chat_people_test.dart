import 'dart:async';

import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/repositories/people_repository.dart';
import 'package:connectum/data/socket/read_gate.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/chats/models/chat_person.dart';
import 'package:connectum/features/chats/models/person_link.dart';
import 'package:connectum/features/chats/new_chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../inbox/inbox_support.dart' show GateClock;
import '../support/fake_socket.dart';

class _Api extends Fake implements ApiClient {
  @override
  Future<Map<String, dynamic>> session() async => {'mode': 'strict'};
}

class _Convs extends FakeConversations {
  @override
  String get listScope => 'none';
}

Map<String, dynamic> _person(String u, {bool connected = false}) => {
  'username': u,
  'name': u.toUpperCase(),
  'designation': 'Nurse',
  'connected': connected,
};

Map<String, dynamic> _req(
  int id,
  String from,
  String subject, {
  String direction = 'outgoing',
  String type = 'associate',
  String status = 'pending',
}) => {
  'id': id,
  'type': type,
  'status': status,
  'from': from,
  'subject': subject,
  'approvers': [subject],
  'direction': direction,
};

Map<String, dynamic> _event(String name, Map<String, dynamic> data) => {
  'type': 'sd_event',
  'event': name,
  'data': data,
};

void main() {
  late FakeSocket socket;
  late PeopleRepository repo;
  late NewChatController c;
  late GateClock clock;

  setUp(() {
    clock = GateClock();
    socket = FakeSocket()..goOnline();
    repo = PeopleRepository(
      socket,
      ReadGate(now: clock.read, delay: clock.delay),
    );
    c = NewChatController(
      conversations: _Convs(),
      people: repo,
      socket: socket,
      api: _Api(),
      store: FakeStore(user: 'me'),
      connectivity: FakeConnectivity(),
    );
    socket.answers['assoc.list'] = {'associates': []};
    socket.answers['req.list'] = {'requests': [], 'hasMore': false};
  });

  tearDown(() => c.onClose());

  group('users.colleagues, the web\'s shape', () {
    // Shape of sd_cmds_people.erl `users.colleagues`: the cursor is
    // name<NUL>username, avatar is null or an address, no email or mobile.
    Map<String, dynamic> real() => {
      'people': [
        {
          'username': 'asha',
          'name': 'Asha Rao',
          'designation': 'Nurse',
          'department': 'ICU',
          'branch': null,
          'avatar': null,
          'connected': true,
          'online': true,
        },
        {
          'username': 'ravi',
          'name': null,
          'designation': null,
          'department': null,
          'branch': 'HQ',
          'avatar': '/files/a.png',
          'connected': false,
          'online': false,
        },
      ],
      'hasMore': true,
      'next': 'ravi\u0000ravi',
    };

    test('asks like the web: q present and empty, limit 30', () async {
      socket.answers['users.colleagues'] = real();
      await c.prepare();
      expect(
        socket.calls.firstWhere((x) => x.action == 'users.colleagues').args,
        {'q': '', 'limit': 30},
      );
    });

    test('null fields parse; connected splits the two sections', () async {
      socket.answers['users.colleagues'] = real();
      await c.prepare();
      expect(c.connectedPeople.map((p) => p.username), ['asha']);
      expect(c.otherPeople.map((p) => p.username), ['ravi']);
      expect(c.otherPeople.single.name, 'ravi');
      expect(c.hasMore.value, isTrue);
      await c.loadMore();
      expect(socket.calls.last.args['after'], 'ravi\u0000ravi');
    });

    test(
      'an answer without a people list is an error, not an empty list',
      () async {
        socket.answers['users.colleagues'] = {'hasMore': false};
        await c.prepare();
        expect(c.hasFailed.value, isTrue);
        expect(c.listState.name, 'error');
        expect(c.failureReason.value, contains('could not read'));
      },
    );

    test('a server refusal shows its reason', () async {
      socket.answers['users.colleagues'] = const SocketCallError('forbidden');
      await c.prepare();
      expect(c.hasFailed.value, isTrue);
      expect(c.failureReason.value, contains('organisation'));
    });

    test('a really empty list is empty, not an error', () async {
      socket.answers['users.colleagues'] = {
        'people': [],
        'hasMore': false,
        'next': null,
      };
      await c.prepare();
      expect(c.hasFailed.value, isFalse);
      expect(c.listState.name, 'empty');
    });
  });

  group('paging', () {
    setUp(() {
      socket.answers['users.colleagues'] = (Map<String, dynamic> a) {
        final after = a['after'];
        if (after == null) {
          return {
            'people': [_person('a', connected: true), _person('b')],
            'hasMore': true,
            'next': 'n1',
          };
        }
        return {
          'people': [_person('b'), _person('c')],
          'hasMore': false,
          'next': null,
        };
      };
    });

    test(
      'first page on open, next page by cursor, none after the last',
      () async {
        await c.prepare();
        expect(c.colleagues.map((p) => p.username), ['a', 'b']);
        expect(c.hasMore.value, isTrue);
        expect(
          socket.calls.firstWhere((x) => x.action == 'users.colleagues').args,
          {'q': '', 'limit': PeopleRepository.pageSize},
        );

        await c.loadMore();
        expect(c.colleagues.map((p) => p.username), ['a', 'b', 'c']);
        expect(socket.calls.last.args['after'], 'n1');
        expect(c.hasMore.value, isFalse);

        await c.loadMore();
        expect(socket.count('users.colleagues'), 2);
      },
    );

    test('one page at a time', () async {
      await c.prepare();
      final gate = Completer<void>();
      socket.held['users.colleagues'] = gate.future;
      final first = c.loadMore();
      final second = c.loadMore();
      gate.complete();
      await Future.wait([first, second]);
      expect(socket.count('users.colleagues'), 2);
    });

    test('a failed page keeps the rows and waits for a retry', () async {
      await c.prepare();
      socket.answers['users.colleagues'] = const SocketCallError('internal');
      await c.loadMore();
      expect(c.hasLoadMoreFailed.value, isTrue);
      expect(c.colleagues, hasLength(2));
      await c.loadMore();
      expect(socket.count('users.colleagues'), 2);
    });

    test('connected people on top, the rest under Not connected', () async {
      await c.prepare();
      expect(c.connectedPeople.map((p) => p.username), ['a']);
      expect(c.otherPeople.map((p) => p.username), ['b']);
    });

    test('typing reads once after 300 ms and clearing reads nothing', () async {
      await c.prepare();
      final before = socket.count('users.colleagues');
      c.onQueryChanged('b');
      c.onQueryChanged('bo');
      c.onQueryChanged('bob');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(socket.count('users.colleagues'), before);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(socket.count('users.colleagues'), before + 1);
      expect(
        socket.calls
            .where((x) => x.action == 'users.colleagues')
            .last
            .args['q'],
        'bob',
      );
      expect(socket.count('users.search'), 1);

      c.onQueryChanged('');
      expect(c.colleagues.map((p) => p.username), ['a', 'b']);
      expect(socket.count('users.colleagues'), before + 1);
    });

    test('every read goes through the gate', () async {
      final gate = ReadGate(now: clock.read, delay: clock.delay);
      final r = PeopleRepository(socket, gate);
      await r.colleagues();
      await r.connections();
      await r.pendingLinks('me');
      await r.search('bob');
      expect(gate.sent, 4);
      await r.invite('bob');
      expect(gate.sent, 4);
    });
  });

  group('state join', () {
    test('pending requests become Requested and Asked', () async {
      socket.answers['users.colleagues'] = {
        'people': [
          _person('bob'),
          _person('carl'),
          _person('dina'),
          _person('eve', connected: true),
        ],
        'hasMore': false,
      };
      socket.answers['req.list'] = {
        'requests': [
          _req(1, 'me', 'bob'),
          _req(2, 'carl', 'me', direction: 'incoming'),
          _req(3, 'me', 'dina', type: 'group_invite'),
          _req(4, 'me', 'zed', status: 'accepted'),
        ],
        'hasMore': false,
      };
      await c.prepare();
      PersonLink of(String u) =>
          c.linkOf(c.colleagues.firstWhere((p) => p.username == u));
      expect(of('bob'), PersonLink.requested);
      expect(of('carl'), PersonLink.asked);
      expect(of('dina'), PersonLink.none);
      expect(of('eve'), PersonLink.connected);
    });

    test('req.list is read page by page', () async {
      var n = 0;
      socket.answers['req.list'] = (Map<String, dynamic> a) {
        n++;
        return a['offset'] == null
            ? {
                'requests': [_req(1, 'me', 'bob')],
                'hasMore': true,
              }
            : {
                'requests': [_req(2, 'me', 'ann')],
                'hasMore': false,
              };
      };
      final links = await repo.pendingLinks('me');
      expect(n, 2);
      expect(links, {'bob': PersonLink.requested, 'ann': PersonLink.requested});
      expect(socket.calls.last.args['offset'], 1);
    });

    test('events move a row live', () async {
      socket.answers['users.colleagues'] = {
        'people': [_person('bob'), _person('carl')],
        'hasMore': false,
      };
      await c.prepare();
      ChatPerson p(String u) => c.colleagues.firstWhere((x) => x.username == u);

      c.onSocketEvent(
        _event('request_created', _req(5, 'carl', 'me', direction: 'incoming')),
      );
      expect(c.linkOf(p('carl')), PersonLink.asked);

      c.onSocketEvent(
        _event('request_resolved', _req(5, 'carl', 'me', status: 'accepted')),
      );
      expect(c.linkOf(p('carl')), PersonLink.connected);
      expect(c.connectedPeople.map((x) => x.username), ['carl']);

      await c.connect(p('bob'));
      expect(c.linkOf(p('bob')), PersonLink.requested);
      c.onSocketEvent(
        _event('request_resolved', _req(6, 'me', 'bob', status: 'rejected')),
      );
      expect(c.linkOf(p('bob')), PersonLink.none);

      c.onSocketEvent(
        _event('request_created', _req(7, 'me', 'x', type: 'submission')),
      );
      expect(c.links.containsKey('x'), isFalse);
    });
  });

  group('error mapping', () {
    test('the six codes of assoc.invite', () {
      InviteError e(String code) =>
          PeopleRepository.explain(SocketCallError(code));
      expect(e('invalid').message, contains('yourself'));
      expect(e('not_found').message, contains("couldn't be found"));
      expect(e('already_associated').fix, InviteFix.isConnected);
      expect(e('forbidden').message, contains("rules don't allow"));
      expect(e('duplicate').fix, InviteFix.isRequested);
      expect(e('rate_limited').message, contains('Too many'));
      for (final code in [
        'invalid',
        'not_found',
        'forbidden',
        'rate_limited',
      ]) {
        expect(e(code).fix, InviteFix.rollBack);
      }
    });

    test('a connection gap and an unknown code get their own words', () {
      expect(
        PeopleRepository.explain(const SocketCallError('timeout')).message,
        contains('connection'),
      );
      expect(
        PeopleRepository.explain(const SocketCallError('weird')).message,
        contains('Try again'),
      );
    });
  });

  group('connect', () {
    late ChatPerson bob;
    setUp(() async {
      socket.answers['users.colleagues'] = {
        'people': [_person('bob')],
        'hasMore': false,
      };
      await c.prepare();
      bob = c.colleagues.single;
    });

    test('sends assoc.invite and stays Requested', () async {
      socket.answers['assoc.invite'] = {'request': _req(9, 'me', 'bob')};
      await c.connect(bob);
      expect(socket.calls.last.action, 'assoc.invite');
      expect(socket.calls.last.args, {'to': 'bob'});
      expect(c.linkOf(bob), PersonLink.requested);
      expect(c.explanation.value, isNull);
    });

    test('shows Requested while sending and blocks a second send', () async {
      final gate = Completer<void>();
      socket.held['assoc.invite'] = gate.future;
      final first = c.connect(bob);
      await Future<void>.delayed(Duration.zero);
      expect(c.linkOf(bob), PersonLink.requested);
      expect(c.sending, contains('bob'));
      await c.connect(bob);
      gate.complete();
      await first;
      expect(socket.count('assoc.invite'), 1);
      expect(c.sending, isEmpty);
    });

    for (final code in [
      'invalid',
      'not_found',
      'forbidden',
      'rate_limited',
      'timeout',
    ]) {
      test('$code rolls back to Connect with a message', () async {
        socket.answers['assoc.invite'] = SocketCallError(code);
        await c.connect(bob);
        expect(c.linkOf(bob), PersonLink.none);
        expect(c.sending, isEmpty);
        expect(c.explanation.value, isNotNull);
        expect(c.explanationValues['name'], 'BOB');
        await c.connect(bob);
        expect(socket.count('assoc.invite'), 2);
      });
    }

    test(
      'duplicate keeps Requested, already_associated becomes Connected',
      () async {
        socket.answers['assoc.invite'] = const SocketCallError('duplicate');
        await c.connect(bob);
        expect(c.linkOf(bob), PersonLink.requested);
        expect(c.explanation.value, contains('already waiting'));

        c.links.clear();
        socket.answers['assoc.invite'] = const SocketCallError(
          'already_associated',
        );
        await c.connect(bob);
        expect(c.linkOf(bob), PersonLink.connected);
      },
    );

    test('an unexpected error rolls back', () async {
      socket.answers['assoc.invite'] = (Map<String, dynamic> a) =>
          throw StateError('boom');
      await c.connect(bob);
      expect(c.linkOf(bob), PersonLink.none);
      expect(c.sending, isEmpty);
    });

    test('nothing is sent when Requested, Connected or offline', () async {
      c.links['bob'] = PersonLink.requested;
      await c.connect(bob);
      expect(socket.count('assoc.invite'), 0);
      c.links.clear();
      socket.goOffline();
      await c.connect(bob);
      expect(socket.count('assoc.invite'), 0);
      expect(c.linkOf(bob), PersonLink.none);
    });
  });
}
