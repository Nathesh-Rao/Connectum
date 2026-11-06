import '../models/hash_command.dart';

/// A message box line read as a `#` command: `#name arg arg rest of the line`.
/// The server is the judge; this only reads the line the way it does and
/// catches the obvious mistakes before sending.
class CommandLine {
  const CommandLine(this.name, this.rest, this.hasSpace);

  static final _start = RegExp(r'^#[A-Za-z]');
  static final _name = RegExp(r'^#([A-Za-z][A-Za-z0-9_-]*)');

  /// Name as typed, lower case.
  final String name;

  /// Everything after the name and the one space that follows it.
  final String rest;

  /// True once a space follows the name (the name is complete).
  final bool hasSpace;

  /// True when the text, ignoring leading spaces, is in command mode: `#` and
  /// nothing else, or `#` and a letter. `#1 priority`, `# x` and `##x` are
  /// ordinary text for the menu.
  static bool opensMenu(String text) {
    final t = text.trimLeft();
    return t == '#' || _start.hasMatch(t);
  }

  /// A line the server runs as a command: `#` followed by a letter.
  static bool isCommand(String text) => _start.hasMatch(text.trimLeft());

  /// `##text`: a message to the general room, not available in the app.
  static bool isEscape(String text) => text.trimLeft().startsWith('##');

  static CommandLine? parse(String text) {
    final t = text.trimLeft();
    final m = _name.firstMatch(t);
    if (m == null) return null;
    final after = t.substring(m.end);
    final hasSpace = after.isNotEmpty && after[0] == ' ';
    return CommandLine(
      m.group(1)!.toLowerCase(),
      hasSpace ? after.substring(1) : after,
      hasSpace,
    );
  }

  /// Splits [rest] by [command]'s arguments, by position. [groupNames] are the
  /// known multi-word names for `group` and `host` arguments (longest wins).
  CommandArgs bind(
    HashCommand command, {
    Iterable<String> groupNames = const [],
  }) {
    final names = groupNames.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var left = rest;
    final values = <String, String>{};
    final args = command.args;
    for (var i = 0; i < args.length && left.isNotEmpty; i++) {
      final a = args[i];
      if (a.isRest || (a.type == 'text' && i == args.length - 1)) {
        values[a.name] = left;
        left = '';
        break;
      }
      if (a.isPhrase || a.type == 'phrase') {
        final later = args.skip(i + 1).where((x) => x.isRequired).length;
        final words = left.split(' ');
        final take = (words.length - later).clamp(1, words.length);
        values[a.name] = words.take(take).join(' ');
        left = words.skip(take).join(' ');
        continue;
      }
      var token = '';
      if (a.type == 'group' || a.type == 'host') {
        final low = left.toLowerCase();
        for (final n in names) {
          final l = n.toLowerCase();
          if (low == l || low.startsWith('$l ')) {
            token = left.substring(0, n.length);
            break;
          }
        }
      }
      if (token.isEmpty) {
        final cut = left.indexOf(' ');
        token = cut < 0 ? left : left.substring(0, cut);
      }
      values[a.name] = token;
      left = left.length > token.length ? left.substring(token.length + 1) : '';
    }
    return CommandArgs(values, left);
  }
}

/// The arguments of one line by name, and what was left after the last one.
class CommandArgs {
  const CommandArgs(this.values, this.extra);

  final Map<String, String> values;
  final String extra;

  String? operator [](String name) => values[name];
}

/// The checks the server makes on arguments, with its messages. Anything the
/// catalogue does not describe passes.
class CommandValidator {
  CommandValidator._();

  static final _control = RegExp(r'[\u0000-\u001F\u007F-\u009F]');

  /// The first problem in [args], or null.
  static String? check(HashCommand command, CommandArgs args) {
    for (final a in command.args) {
      final v = args[a.name];
      if (v == null || v.isEmpty) {
        if (a.isRequired) return 'Missing ${a.name}.';
        continue;
      }
      final problem = _checkOne(a, v);
      if (problem != null) return problem;
    }
    return null;
  }

  static String? _checkOne(CommandArg a, String v) {
    switch (a.type) {
      case 'text':
      case 'phrase':
        final max = a.max;
        if (max != null && v.runes.length > max) {
          return '${a.name} is too long (max $max characters).';
        }
        return null;
      case 'msgid':
        if (!RegExp(r'^\d{1,18}$').hasMatch(v)) {
          return '${a.name} must be a number.';
        }
        return null;
      case 'enum':
        if (a.values.isEmpty) return null;
        final low = v.toLowerCase();
        if (!a.values.any((x) => x.toLowerCase() == low)) {
          return '${a.name} must be one of: ${a.values.join(', ')}.';
        }
        return null;
      case 'url':
        final ok =
            v.startsWith('http://') ||
            v.startsWith('https://') ||
            v.startsWith('/uploads/');
        if (!ok) return '${a.name} must be a link (http://, https://).';
        if (v.length > 512) {
          return '${a.name} is too long (max 512 characters).';
        }
        return null;
      case 'emoji':
        if (v.runes.length > 32) {
          return '${a.name} is too long (max 32 characters).';
        }
        return _noControl(a, v);
      case 'word':
        if (v.runes.length > 64) {
          return '${a.name} is too long (max 64 characters).';
        }
        return _noControl(a, v);
      default:
        return _noControl(a, v);
    }
  }

  static String? _noControl(CommandArg a, String v) => _control.hasMatch(v)
      ? '${a.name} has characters that are not allowed.'
      : null;
}
