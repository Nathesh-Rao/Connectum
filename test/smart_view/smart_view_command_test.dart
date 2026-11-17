import 'dart:async';

import 'package:connectum/core/debug/seed_commands.dart';
import 'package:connectum/core/widgets/app_notices.dart';
import 'package:connectum/data/commands/command_menu.dart';
import 'package:connectum/data/commands/command_reply.dart';
import 'package:connectum/data/models/hash_command.dart';
import 'package:connectum/data/repositories/command_repository.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/smart_view/models/sv_source.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/commands/command_runner.dart';
import 'package:connectum/features/conversation/models/command_prompt.dart';
import 'package:connectum/features/home_shell/home_shell_controller.dart';
import 'package:connectum/features/smart_view/models/smart_view_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';

class _Socket extends FakeSocket {
  final lines = <String>[];
  final _bus = StreamController<Map<String, dynamic>>.broadcast();

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

/// The source list the app holds: counts how often it is read.
class _Sources extends Fake implements SmartViewRepository {
  _Sources(this.all);

  List<SvSource> all;
  Object? failure;
  int reads = 0;

  @override
  Future<List<SvSource>> sources({bool isForced = false}) async {
    reads++;
    final f = failure;
    if (f is SocketCallError) throw f;
    return all;
  }
}

const _leave = SvSource(name: 'leave_request', caption: 'Leave request');
const _expense = SvSource(name: 'expense', caption: 'Expense claim');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the # command', () {
    late _Socket socket;
    late CommandRepository repo;

    setUp(() async {
      socket = _Socket()..goOnline();
      repo = CommandRepository(
        socket,
        _Store() as SessionStore,
        FakeConnectivity(),
        _Messages(),
        FakeConversations() as ConversationRepository,
        replyWait: const Duration(milliseconds: 80),
      );
      await repo.ensureLoaded();
      socket.calls.clear();
      socket.lines.clear();
    });

    test('view, smartview and list are one local command', () {
      final view = repo.find('view')!;
      expect(view.isLocal, isTrue);
      expect(view.aliases, containsAll(['smartview', 'list']));
      expect(repo.find('smartview')?.name, 'view');
      expect(repo.find('list')?.name, 'view');
      expect(repo.find('LIST')?.name, 'view');
      expect(view.args.single.type, 'source');
      expect(view.args.single.isRest, isTrue);
      expect(view.isAvailable, isTrue);
      expect(view.requires, 'none');
    });

    test('it is in the menu, once', () {
      expect(repo.menu('vie').map((c) => c.name), contains('view'));
      expect(repo.menu('smartv').map((c) => c.name), ['view']);
      expect(repo.menu('').where((c) => c.name == 'view').length, 1);
    });

    test(
      'the line is read, the name keeps its spaces, nothing is sent',
      () async {
        for (final line in const [
          '#view leave request',
          '#smartview leave request',
          '#list leave request',
          '#VIEW   leave request  ',
        ]) {
          final r = await repo.run(line);
          expect(r.kind, HashKind.smartView, reason: line);
          expect(r.target, 'leave request', reason: line);
        }
        final bare = await repo.run('#view');
        expect(bare.kind, HashKind.smartView);
        expect(bare.target, '');
        expect(socket.lines.where((l) => l.contains('view')), isEmpty);
        expect(socket.lines.where((l) => l.contains('list')), isEmpty);
        expect(socket.calls, isEmpty);
      },
    );

    test(
      'the server catalogue never gets #view, and it wins when it has one',
      () {
        expect(
          CommandMenu.localEntries(const []).map((c) => c.name),
          contains('view'),
        );
        final server = [
          const HashCommand(name: 'view', aliases: ['list']),
        ];
        expect(
          CommandMenu.localEntries(server).map((c) => c.name),
          isNot(contains('view')),
        );
      },
    );

    test('other # commands keep their behaviour', () async {
      expect((await repo.run('#tstruct Leave')).kind, HashKind.records);
      expect((await repo.run('#tstruct-add Leave')).kind, HashKind.form);
      expect((await repo.run('#tasks')).kind, HashKind.screen);
      expect((await repo.run('#find ana')).kind, HashKind.soon);
    });
  });

  group('suggestions after #view', () {
    late _Socket socket;
    late CommandRepository repo;
    late CommandPrompt prompt;
    var asked = <String>[];

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    setUp(() async {
      socket = _Socket()..goOnline();
      repo = CommandRepository(
        socket,
        _Store() as SessionStore,
        FakeConnectivity(),
        _Messages(),
        FakeConversations() as ConversationRepository,
      );
      await repo.ensureLoaded();
      final sources = _Sources([_leave, _expense]);
      asked = [];
      repo.sourceSuggester = (typed) async {
        asked.add(typed);
        return [
          for (final s in SvSources.suggest(await sources.sources(), typed))
            CommandSuggestion(value: s.name, label: s.caption, hint: s.hint),
        ];
      };
      prompt = CommandPrompt(repo);
    });

    tearDown(() => prompt.dispose());

    test('they come from the source list, never from /cmdcomplete', () async {
      prompt.onTextChanged('#view le');
      await settle();
      expect(prompt.items.map((i) => i.value), ['leave_request']);
      expect(prompt.items.single.label, 'Leave request');
      expect(prompt.argName.value, 'name');
      expect(socket.lines.where((l) => l.startsWith('/cmdcomplete')), isEmpty);
      prompt.onTextChanged('#list ');
      await settle();
      expect(prompt.items.length, 2);
      expect(socket.lines.where((l) => l.startsWith('/cmdcomplete')), isEmpty);
    });

    test('picking one replaces everything typed after the command', () async {
      prompt.onTextChanged('#view leave re');
      await settle();
      expect(prompt.insert(prompt.items.single), '#view leave_request ');
    });

    test('a failing list shows no choices and no crash', () async {
      repo.sourceSuggester = (_) async =>
          throw const SocketCallError('timeout');
      prompt.onTextChanged('#view x');
      await settle();
      expect(prompt.items, isEmpty);
      expect(prompt.isLoadingItems.value, isFalse);
    });
  });

  group('the runner', () {
    late _Sources sources;
    late CommandRunner runner;
    late _RunnerCommands commands;
    late _Shell shell;

    Future<void> boot(WidgetTester tester) async {
      sources = _Sources([_leave, _expense]);
      commands = _RunnerCommands();
      shell = _Shell();
      runner = CommandRunner(
        commands,
        CommandPrompt(commands),
        smartView: sources,
        shell: shell,
      );
      await tester.pumpWidget(
        GetMaterialApp(
          home: const AppNoticeHost(child: Scaffold(body: Text('chat'))),
        ),
      );
    }

    Future<bool> run(WidgetTester tester, String line, String target) async {
      commands.target = target;
      late bool cleared;
      await tester.runAsync(() async => cleared = await runner.run(line));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return cleared;
    }

    testWidgets('a name opens that structure, clears the box, posts nothing', (
      tester,
    ) async {
      await boot(tester);
      expect(await run(tester, '#view leave', 'leave'), isTrue);
      expect(shell.entries.single.kind, SmartViewEntryKind.named);
      expect(shell.entries.single.name, 'leave_request');
      expect(commands.lines, ['#view leave']);
      expect(sources.reads, 1);
    });

    testWidgets('a wrong name keeps the text and says so', (tester) async {
      await boot(tester);
      expect(await run(tester, '#view zzz', 'zzz'), isFalse);
      expect(find.text('chat'), findsOneWidget);
      expect(shell.entries, isEmpty);
      expect(
        find.text('Nothing is called “zzz” that you can open.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('no name opens the tab with the drawer open, reads nothing', (
      tester,
    ) async {
      await boot(tester);
      expect(await run(tester, '#view', ''), isTrue);
      expect(shell.entries.single.kind, SmartViewEntryKind.drawer);
      expect(sources.reads, 0);
      expect(commands.lines, ['#view']);
    });

    testWidgets('no connection and no list: the usual notice, text kept', (
      tester,
    ) async {
      await boot(tester);
      sources.failure = const SocketCallError('not_connected');
      expect(await run(tester, '#view leave', 'leave'), isFalse);
      expect(find.text('Needs a connection'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });
  });
}

class _Shell extends Fake implements HomeShellController {
  final entries = <SmartViewEntry>[];

  @override
  void openSmartView(SmartViewEntry entry) => entries.add(entry);
}

/// `run` answers `smartView` with the target the test sets.
class _RunnerCommands extends Fake implements CommandRepository {
  String target = '';
  final lines = <String>[];

  @override
  CommandSuggester createSuggester() =>
      CommandSuggester((_, _, _) async => null);

  @override
  Future<HashResult> run(
    String line, {
    String? activeConvId,
    bool isConfirmed = false,
  }) async {
    lines.add(line);
    return HashResult(
      HashKind.smartView,
      '',
      '',
      '',
      '',
      const [],
      const [],
      target,
    );
  }
}
