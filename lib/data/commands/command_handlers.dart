import '../models/hash_command.dart';

/// What the app does when a command is run.
enum CommandMode {
  /// Open the chat and leave the text in its message box, unsent.
  draft,

  /// Send the `#` line and show the answer.
  line,

  /// Send the line and show the people or groups that come back.
  list,

  /// An app screen or sheet; nothing is sent.
  screen,

  /// Not in the app yet.
  soon,
}

class CommandHandler {
  const CommandHandler(this.mode, [this.target = '']);

  final CommandMode mode;

  /// `screen`/`list`: what to open (`inbox`, `tasks`, `help`, `users`,
  /// `groups`, `associates`).
  final String target;

  /// Asks before running.
  bool get isRisky => target == 'leavegroup';
}

/// The one place that says what each command does in the app: a new command
/// is one entry here. Custom commands always run on the server.
class CommandHandlers {
  CommandHandlers._();

  static const _byName = <String, CommandHandler>{
    'dm': CommandHandler(CommandMode.draft, 'dm'),
    'groupmsg': CommandHandler(CommandMode.draft, 'group'),
    'creategroup': CommandHandler(CommandMode.line, 'creategroup'),
    'addmember': CommandHandler(CommandMode.line, 'addmember'),
    'leavegroup': CommandHandler(CommandMode.line, 'leavegroup'),
    'users': CommandHandler(CommandMode.list, 'users'),
    'groups': CommandHandler(CommandMode.list, 'groups'),
    'associates': CommandHandler(CommandMode.list, 'associates'),
    'connections': CommandHandler(CommandMode.list, 'associates'),
    'inbox': CommandHandler(CommandMode.screen, 'inbox'),
    'tasks': CommandHandler(CommandMode.screen, 'tasks'),
    'help': CommandHandler(CommandMode.screen, 'help'),
  };

  static CommandHandler of(HashCommand c) {
    if (c.isCustom) return const CommandHandler(CommandMode.line, 'custom');
    return _byName[c.name] ?? const CommandHandler(CommandMode.soon);
  }

  /// Only these accept `/c <clientId> #...`.
  static const idempotent = {'creategroup', 'addmember'};
}
