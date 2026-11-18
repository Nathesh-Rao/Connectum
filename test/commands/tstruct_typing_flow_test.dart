import 'dart:async';
import 'dart:convert';

import 'package:connectum/core/debug/seed_commands.dart';
import 'package:connectum/data/commands/command_reply.dart';
import 'package:connectum/data/models/hash_command.dart';
import 'package:connectum/data/repositories/command_repository.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/features/conversation/models/command_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

/// Answers `/cmds` with the catalogue and `/cmdcomplete` the way the server
/// does for a `phrase` argument: the structures whose caption starts with the
/// word typed after the command.
class _Socket extends FakeSocket {
  final lines = <String>[];
  final _bus = StreamController<Map<String, dynamic>>.broadcast();

  static const captions = ['Leave Request', 'Expense Claim', 'Lead Capture'];

  @override
  Stream<Map<String, dynamic>> get events => _bus.stream;

  @override
  bool isCurrent(Map<String, dynamic> event) => true;

  @override
  Future<bool> sendCommand(String line) async {
    if (!isOnline) return false;
    lines.add(line);
    if (line == '/cmds') {
      scheduleMicrotask(() => _bus.add(SeedCommands.catalogFrame()));
    }
    if (line.startsWith('/cmdcomplete ')) {
      final body = jsonDecode(line.substring(13)) as Map<String, dynamic>;
      final input = body['input'] as String;
      final at = input.indexOf(' ');
      final typed = at < 0 ? '' : input.substring(at + 1);
      scheduleMicrotask(
        () => _bus.add({
          'type': 'cmd_suggestions',
          'reqId': body['reqId'],
          'kind': 'arg',
          'token': typed,
          'arg': {'name': 'name', 'index': 0},
          'items': [
            for (final c in captions)
              if (c.toLowerCase().startsWith(typed.toLowerCase()))
                {
                  'value': c,
                  'label': c,
                  'hint': c.toLowerCase().replaceAll(' ', '_'),
                },
          ],
          'page': 1,
          'hasMore': false,
        }),
      );
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

class _Messages extends Fake implements MessageRepository {}

/// The box and the menu, driven the way ConversationController does it:
/// `onChanged` for typing, `_setText` for a pick.
class _Box {
  _Box(this.prompt);

  final CommandPrompt prompt;
  String text = '';

  void type(String value) {
    text = value;
    prompt.onTextChanged(value);
  }

  void pickCommand(HashCommand c) => type('#${c.name} ');

  void pickName(CommandSuggestion s) {
    text = prompt.insert(s);
    prompt.onTextChanged(text);
  }

  String get mode => prompt.command.value != null
      ? 'names'
      : prompt.query.value != null
      ? 'commands'
      : 'closed';
}

void main() {
  late _Socket socket;
  late CommandRepository repo;
  late CommandPrompt prompt;
  late _Box box;

  setUp(() async {
    socket = _Socket()..goOnline();
    repo = CommandRepository(
      socket,
      _Store() as SessionStore,
      FakeConnectivity(),
      _Messages(),
      FakeConversations() as ConversationRepository,
      replyWait: const Duration(milliseconds: 200),
    );
    await repo.ensureLoaded();
    prompt = CommandPrompt(repo);
    box = _Box(prompt);
  });

  tearDown(() => prompt.dispose());

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  List<String> values() => [for (final i in prompt.items) i.value];

  for (final cmd in const ['tstruct', 'tstruct-add']) {
    final other = cmd == 'tstruct' ? 'tstruct-add' : 'tstruct';

    test('#$cmd: typing and picking follows the web step by step', () async {
      // a) `#` opens the command menu
      box.type('#');
      expect(box.mode, 'commands');
      expect(prompt.matches.map((c) => c.name), containsAll([cmd, other]));

      // b) picking the command row writes `#cmd ` and asks for the names
      box.pickCommand(prompt.matches.firstWhere((c) => c.name == cmd));
      expect(box.text, '#$cmd ');
      expect(box.mode, 'names');
      await settle();
      expect(values(), _Socket.captions, reason: 'names after `#$cmd `');

      // c) `#cmd` without a space: the command menu, no names yet
      box.type('#$cmd');
      expect(box.mode, 'commands');
      expect(prompt.items, isEmpty);
      expect(box.text, '#$cmd');

      // d) `#cmd ` with a space: the names
      box.type('#$cmd ');
      expect(box.mode, 'names');
      await settle();
      expect(values(), _Socket.captions);

      // e) `#cmd le` narrows the names
      box.type('#$cmd le');
      await settle();
      expect(values(), ['Leave Request', 'Lead Capture']);

      // f) picking a name replaces the word, adds no space
      box.pickName(prompt.items.first);
      expect(box.text, '#$cmd Leave Request');

      // g) send: the line names the structure
      final r = await repo.run(box.text);
      expect(r.kind, cmd == 'tstruct' ? HashKind.records : HashKind.form);
      expect(r.target, 'Leave Request');
    });

    test('#$cmd: a bare send gives the web tip and opens nothing', () async {
      final r = await repo.run('#$cmd');
      expect(r.kind, HashKind.usage);
      expect(r.text, CommandRepository.noStructure(cmd));
    });
  }
}
