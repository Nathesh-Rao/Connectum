import 'package:connectum/core/debug/seed_commands.dart';
import 'package:connectum/data/commands/command_line.dart';
import 'package:connectum/data/commands/command_menu.dart';
import 'package:connectum/data/models/hash_command.dart';
import 'package:flutter_test/flutter_test.dart';

final _catalog = [
  for (final j in SeedCommands.catalogFrame()['commands'] as List)
    HashCommand.fromJson((j as Map).cast<String, dynamic>()),
];
final _categories = [
  for (final c in SeedCommands.catalogFrame()['categories'] as List)
    CommandCategory((c as Map)['id'] as String, c['label'] as String),
];

HashCommand _cmd(String name) => CommandMenu.find(_catalog, name)!;

void main() {
  group('reading the line', () {
    test('name, aliases and case', () {
      final l = CommandLine.parse('  #DM ana hi there')!;
      expect(l.name, 'dm');
      expect(l.rest, 'ana hi there');
      expect(l.hasSpace, isTrue);
      expect(_cmd(l.name).name, 'dm');
      expect(CommandMenu.find(_catalog, 'MSG')!.name, 'dm');
      expect(CommandMenu.find(_catalog, 'd'), isNull);
    });

    test('"#1 priority", "# x", "##x" are not commands', () {
      expect(CommandLine.isCommand('#1 priority'), isFalse);
      expect(CommandLine.isCommand('# 5'), isFalse);
      expect(CommandLine.isCommand('##text'), isFalse);
      expect(CommandLine.isEscape('##text'), isTrue);
      expect(CommandLine.opensMenu('#'), isTrue);
      expect(CommandLine.opensMenu('#d'), isTrue);
      expect(CommandLine.opensMenu('#1 x'), isFalse);
      expect(CommandLine.opensMenu('hello #dm'), isFalse);
    });

    test('rest text is the last argument', () {
      final cmd = _cmd('dm');
      final args = CommandLine.parse('#dm ana hello big  world')!.bind(cmd);
      expect(args['user'], 'ana');
      expect(args['text'], 'hello big  world');
    });

    test('group names with spaces: the longest known name wins', () {
      final cmd = _cmd('groupmsg');
      final args = CommandLine.parse(
        '#groupmsg team a lead hi all',
      )!.bind(cmd, groupNames: ['Team A', 'Team A Lead']);
      expect(args['group'], 'team a lead');
      expect(args['text'], 'hi all');
    });

    test('an unknown group falls back to one word', () {
      final args = CommandLine.parse(
        '#groupmsg nobody hi',
      )!.bind(_cmd('groupmsg'), groupNames: ['Team A']);
      expect(args['group'], 'nobody');
      expect(args['text'], 'hi');
    });
  });

  group('validator', () {
    String? check(String line, {List<String> groups = const []}) {
      final l = CommandLine.parse(line)!;
      final cmd = _cmd(l.name);
      return CommandValidator.check(cmd, l.bind(cmd, groupNames: groups));
    }

    test('missing', () {
      expect(check('#dm ana'), 'Missing text.');
      expect(check('#dm '), 'Missing user.');
      expect(check('#dm ana hi'), isNull);
    });

    test('too long', () {
      expect(
        check('#dm ana ${'x' * 2001}'),
        'text is too long (max 2000 characters).',
      );
    });

    test('enum is case-insensitive', () {
      expect(check('#rate HIGH'), isNull);
      expect(
        check('#rate extreme'),
        'level must be one of: low, medium, high.',
      );
    });

    test('msgid is digits, 18 at most', () {
      expect(check('#react 123 x'), isNull);
      expect(check('#react 12a x'), 'id must be a number.');
      expect(check('#react ${'1' * 19} x'), 'id must be a number.');
    });

    test('url prefixes', () {
      expect(check('#open https://a.b'), isNull);
      expect(check('#open /uploads/x.png'), isNull);
      expect(check('#open ftp://a.b'), isNotNull);
    });

    test('control characters in a single word', () {
      expect(
        check('#dm a\u0001b hi'),
        'user has characters that are not allowed.',
      );
    });

    test('a command the catalogue does not describe passes', () {
      const cmd = HashCommand(name: 'x');
      expect(CommandValidator.check(cmd, const CommandArgs({}, '')), isNull);
    });
  });

  group('menu order and scores', () {
    test('score table', () {
      const c = HashCommand(
        name: 'group',
        aliases: ['team'],
        category: 'people',
        summary: 'Work with a squad',
      );
      expect(CommandMenu.score(c, 'group'), 100);
      expect(CommandMenu.score(c, 'team'), 90);
      expect(CommandMenu.score(c, 'gro'), 80);
      expect(CommandMenu.score(c, 'tea'), 70);
      expect(CommandMenu.score(c, 'oup'), 50);
      expect(CommandMenu.score(c, 'eam'), 40);
      expect(CommandMenu.score(c, 'squad'), 30);
      expect(CommandMenu.score(c, 'peop'), 20);
      expect(CommandMenu.score(c, 'zzz'), 0);
    });

    test('typed text orders by score', () {
      final rows = CommandMenu.filter(
        _catalog,
        'groups',
        categories: _categories,
      );
      expect(rows.first.name, 'groups');
      final prefix = CommandMenu.filter(_catalog, 'gro').map((c) => c.name);
      expect(prefix, containsAll(['groupmsg', 'groups']));
    });

    test('nothing typed groups by category order', () {
      final rows = CommandMenu.filter(_catalog, '', categories: _categories);
      final order = [
        for (final c in rows) _categories.indexWhere((x) => x.id == c.category),
      ];
      expect(order, [...order]..sort());
      expect(rows.first.category, 'messaging');
    });

    test('hidden commands are not offered but still found', () {
      final names = CommandMenu.filter(_catalog, '').map((c) => c.name);
      for (final h in CommandMenu.hidden) {
        expect(names, isNot(contains(h)));
      }
      expect(_cmd('forms').name, 'forms');
    });
  });

  group('permission filter', () {
    const broadcast = HashCommand(name: 'broadcast', aliases: ['announce']);
    const studio = HashCommand(name: 'studio', aliases: ['ide']);
    const invite = HashCommand(name: 'addemployee');
    const admin = HashCommand(name: 'secret', requires: 'admin');

    test('unknown permissions keep them out', () {
      for (final c in [broadcast, studio, invite, admin]) {
        expect(CommandMenu.isOffered(c), isFalse);
      }
    });

    test('held permissions bring them in', () {
      expect(
        CommandMenu.isOffered(broadcast, permissions: {'broadcast'}),
        isTrue,
      );
      expect(
        CommandMenu.isOffered(studio, permissions: {'studio.use'}),
        isTrue,
      );
      expect(
        CommandMenu.isOffered(invite, permissions: {'invite.employees'}),
        isTrue,
      );
      expect(
        CommandMenu.isOffered(studio, permissions: {'broadcast'}),
        isFalse,
      );
    });

    test('admin only for admins', () {
      expect(CommandMenu.isOffered(admin, permissions: {}), isFalse);
      expect(
        CommandMenu.isOffered(admin, permissions: {}, isAdmin: true),
        isTrue,
      );
    });
  });

  test('local entries do not take an alias a server command has', () {
    final local = CommandMenu.localEntries(_catalog);
    final connections = local.firstWhere((c) => c.name == 'connections');
    expect(connections.aliases, isNot(contains('contacts')));
    expect(local.every((c) => c.isLocal), isTrue);
  });
}
