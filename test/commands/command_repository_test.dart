import 'dart:async';

import 'package:connectum/core/debug/seed_commands.dart';
import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/data/repositories/command_repository.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

/// Records every line and answers some of them with frames.
class _Socket extends FakeSocket {
  final lines = <String>[];
  final _bus = StreamController<Map<String, dynamic>>.broadcast();

  /// line prefix -> frames to emit when such a line is sent.
  final replies = <String, List<Map<String, dynamic>>>{};

  @override
  Stream<Map<String, dynamic>> get events => _bus.stream;

  @override
  bool isCurrent(Map<String, dynamic> event) => true;

  void emit(Map<String, dynamic> e) => _bus.add(e);

  @override
  Future<bool> sendCommand(String line) async {
    if (!isOnline) return false;
    lines.add(line);
    for (final entry in replies.entries) {
      if (line.contains(entry.key)) {
        for (final f in entry.value) {
          scheduleMicrotask(() => _bus.add(f));
        }
      }
    }
    return true;
  }
}

class _Store extends FakeStore {
  @override
  Future<String?> readValue(String key) async => null;

  @override
  Future<void> writeValue(String key, String value) async {}
}

class _Conversations extends FakeConversations {
  final saved = <Map<String, dynamic>>[];

  @override
  Future<void> saveGroup(Map<String, dynamic> e) async => saved.add(e);
}

class _Messages extends Fake implements MessageRepository {}

Conversation _dm(String user) =>
    Conversation(convId: 'dm:$user', kind: 'dm', title: user);

Conversation _group(String name) =>
    Conversation(convId: 'group:$name', kind: 'group', title: name);

void main() {
  late _Socket socket;
  late _Conversations conversations;
  late CommandRepository repo;

  setUp(() {
    socket = _Socket()..goOnline();
    socket.replies['/cmds'] = [SeedCommands.catalogFrame()];
    conversations = _Conversations();
    repo = CommandRepository(
      socket,
      _Store() as SessionStore,
      FakeConnectivity(),
      _Messages(),
      conversations as ConversationRepository,
      replyWait: const Duration(milliseconds: 80),
    );
  });

  List<String> hashLines() =>
      socket.lines.where((l) => l != '/cmds' && !l.startsWith('/sd')).toList();

  test('#dm and #groupmsg open a draft and never send a line', () async {
    conversations.conversations.addAll([_dm('ana'), _group('Team A')]);
    final dm = await repo.run('#dm ana hello there');
    expect(dm.kind, HashKind.draft);
    expect(dm.convId, 'dm:ana');
    expect(dm.text, 'hello there');
    final gm = await repo.run('#gm team a hi all');
    expect(gm.kind, HashKind.draft);
    expect(gm.convId, 'group:Team A');
    expect(gm.text, 'hi all');
    expect(hashLines(), isEmpty);
  });

  test('an unknown person or group sends nothing', () async {
    conversations.conversations.add(_group('Team A'));
    socket.answers['users.search'] = <String, dynamic>{'users': []};
    final dm = await repo.run('#dm nobody hi');
    expect(dm.kind, HashKind.error);
    expect(dm.text, CommandRepository.noPerson);
    final gm = await repo.run('#groupmsg nope hi');
    expect(gm.text, CommandRepository.noGroup);
    expect(hashLines(), isEmpty);
  });

  test('"##" is a notice and sends nothing', () async {
    final r = await repo.run('##hello');
    expect(r.kind, HashKind.notice);
    expect(r.text, CommandRepository.escapeNotice);
    expect(socket.lines.where((l) => l.contains('hello')), isEmpty);
  });

  test('a retry of #creategroup reuses the client id', () async {
    final first = await repo.run('#creategroup Alpha');
    expect(first.kind, HashKind.error);
    final second = await repo.run('#creategroup Alpha');
    expect(second.kind, HashKind.error);
    final sent = socket.lines.where((l) => l.endsWith('#creategroup Alpha'));
    expect(sent.length, 2);
    final cids = [for (final l in sent) l.split(' ')[1]];
    expect(cids.first, startsWith('m-'));
    expect(cids.first, cids.last);
    expect(hashLines().every((l) => l.startsWith('/c m-')), isTrue);
  });

  test('a new line gets a new client id; success frees it', () async {
    socket.replies['#creategroup'] = [
      {
        'type': 'group_created',
        'name': 'Alpha',
        'members': ['me'],
      },
    ];
    final ok = await repo.run('#creategroup Alpha');
    expect(ok.kind, HashKind.success);
    expect(ok.text, 'Group created');
    expect(conversations.saved.single['name'], 'Alpha');
    await repo.run('#creategroup Alpha');
    final cids = [
      for (final l in socket.lines.where((l) => l.contains('#creategroup')))
        l.split(' ')[1],
    ];
    expect(cids.first, isNot(cids.last));
  });

  test('duplicate:true counts as success', () async {
    socket.replies['#creategroup'] = [
      {'type': 'group_created', 'name': 'Alpha', 'duplicate': true},
    ];
    expect((await repo.run('#creategroup Alpha')).kind, HashKind.success);
  });

  test('addmember answers and the owner check', () async {
    conversations.conversations.add(
      Conversation(
        convId: 'group:Alpha',
        kind: 'group',
        title: 'Alpha',
        owner: 'boss',
      ),
    );
    final denied = await repo.run('#addmember Alpha ana');
    expect(denied.kind, HashKind.blocked);
    expect(denied.text, 'Only the group admin (boss) can add members');
    expect(hashLines(), isEmpty);
    conversations.conversations.clear();
    socket.replies['#addmember'] = [
      {'type': 'group_invite_pending', 'group': 'Alpha', 'user': 'ana'},
    ];
    final r = await repo.run('#addmember Alpha ana');
    expect(r.text, 'Invitation sent to ana');
  });

  test('leavegroup asks first, then sends', () async {
    conversations.conversations.add(_group('Alpha'));
    final ask = await repo.run('#leave Alpha');
    expect(ask.kind, HashKind.confirm);
    expect(ask.target, 'Alpha');
    expect(hashLines(), isEmpty);
    socket.replies['#leave'] = [
      {'type': 'left_group', 'text': 'Alpha'},
    ];
    final done = await repo.run('#leave Alpha', isConfirmed: true);
    expect(done.kind, HashKind.success);
    expect(done.text, 'You left Alpha');
  });

  test('unknown_command and usage errors reach the screen', () async {
    socket.replies['#zzz'] = [SeedCommands.unknownFrame('zzz')];
    final u = await repo.run('#zzz');
    expect(u.kind, HashKind.unknown);
    expect(u.suggestions, ['dm', 'users', 'groups']);
    final bad = await repo.run('#creategroup');
    expect(bad.kind, HashKind.usage);
    expect(bad.text, 'Missing name. Usage: #creategroup <name>');
  });

  test('users and groups open rows', () async {
    socket.replies['#who'] = [
      {
        'type': 'users',
        'list': ['me', 'ana', 'ravi'],
      },
    ];
    final users = await repo.run('#who');
    expect(users.kind, HashKind.rows);
    expect(users.rows.map((r) => r.title), ['ana', 'ravi']);
    socket.replies['#groups'] = [
      {
        'type': 'groups',
        'list': [
          {
            'name': 'Alpha',
            'members': ['a', 'b'],
          },
        ],
      },
    ];
    final groups = await repo.run('#groups');
    expect(groups.rows.single.convId, 'group:Alpha');
    expect(groups.rows.single.subtitle, '2 members');
  });

  test('other commands say coming soon and send nothing', () async {
    final r = await repo.run('#find ana');
    expect(r.kind, HashKind.soon);
    expect(r.text, CommandRepository.comingSoon);
    expect(hashLines(), isEmpty);
  });

  test('a command the person may not run is refused before sending', () async {
    final r = await repo.run('#transfer ana bob');
    expect(r.kind, HashKind.blocked);
    expect(
      r.text,
      "You don't have access to #transfer. Ask your administrator to give you the permission.",
    );
    expect(hashLines(), isEmpty);
  });

  test('inbox and tasks are screens', () async {
    expect((await repo.run('#inbox')).target, 'inbox');
    expect((await repo.run('#todo')).target, 'tasks');
    expect((await repo.run('#help')).target, 'help');
    expect((await repo.run('#help dm')).target, 'help:dm');
    expect(hashLines(), isEmpty);
  });

  test('offline needs a connection', () async {
    socket.goOffline();
    final r = await repo.run('#groups');
    expect(r.kind, HashKind.needsConnection);
  });
}
