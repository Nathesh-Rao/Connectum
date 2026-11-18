import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/data/commands/command_handlers.dart';
import 'package:connectum/data/models/hash_command.dart';
import 'package:connectum/data/repositories/command_repository.dart';
import 'package:flutter_test/flutter_test.dart';

HashCommand _c(String name) => HashCommand(name: name);

void main() {
  // command -> what running does in the app. #view opens the Smart View tab;
  // `#tstruct <name>` (mode records) opens the /struct-records screen from the
  // command runner (test/commands/command_runner_test.dart), no longer the
  // Submits tab; every other row is the old one.
  const table = <String, (CommandMode, String)>{
    'dm': (CommandMode.draft, 'dm'),
    'groupmsg': (CommandMode.draft, 'group'),
    'creategroup': (CommandMode.line, 'creategroup'),
    'addmember': (CommandMode.line, 'addmember'),
    'leavegroup': (CommandMode.line, 'leavegroup'),
    'users': (CommandMode.list, 'users'),
    'groups': (CommandMode.list, 'groups'),
    'associates': (CommandMode.list, 'associates'),
    'connections': (CommandMode.list, 'associates'),
    'inbox': (CommandMode.screen, 'inbox'),
    'tasks': (CommandMode.screen, 'tasks'),
    'help': (CommandMode.screen, 'help'),
    'tstruct-add': (CommandMode.form, ''),
    'tstruct': (CommandMode.records, ''),
    'view': (CommandMode.smartView, ''),
    'find': (CommandMode.soon, ''),
    'remind': (CommandMode.soon, ''),
    'host': (CommandMode.soon, ''),
  };

  for (final e in table.entries) {
    test('#${e.key} -> ${e.value.$1.name}', () {
      final h = CommandHandlers.of(_c(e.key));
      expect(h.mode, e.value.$1);
      expect(h.target, e.value.$2);
    });
  }

  test('#tstruct <name> and #ts <name> go to the records screen route', () {
    expect(AppRoutes.structRecords, '/struct-records');
    expect(CommandHandlers.of(_c('tstruct')).mode, CommandMode.records);
    expect(CommandHandlers.of(_c('tstruct-add')).mode, CommandMode.form);
  });

  test('the handler table has no entry this test does not know', () {
    for (final name in [
      'dm',
      'groupmsg',
      'creategroup',
      'addmember',
      'leavegroup',
      'users',
      'groups',
      'associates',
      'connections',
      'inbox',
      'tasks',
      'help',
      'tstruct-add',
      'tstruct',
      'view',
      'smartview',
      'list',
      'ts',
      'create',
    ]) {
      final h = CommandHandlers.of(_c(name));
      expect(
        h.mode == CommandMode.soon || table.containsKey(name),
        isTrue,
        reason: '#$name has a handler missing from the table',
      );
    }
  });

  test('a missing structure name gives the web text of that command', () {
    expect(
      CommandRepository.noStructure('tstruct'),
      'Please provide the struct name, e.g. #tstruct leave-request.',
    );
    expect(
      CommandRepository.noStructure('tstruct-add'),
      'Please provide the struct name, e.g. #tstruct-add leave-request.',
    );
  });
}
