import 'ids.dart';

/// One argument of a command (`args` of the catalogue).
class CommandArg {
  const CommandArg({
    required this.name,
    this.type = 'word',
    this.isRequired = false,
    this.values = const [],
    this.isRest = false,
    this.max,
  });

  final String name;
  final String type;
  final bool isRequired;
  final List<String> values;
  final bool isRest;
  final int? max;

  /// A text argument that is not the rest of the line takes every word the
  /// later single-word arguments leave over (the server's `phrase`).
  bool get isPhrase => type == 'text' && !isRest;

  factory CommandArg.fromJson(Map<String, dynamic> j) => CommandArg(
    name: idText(j['name']),
    type: j['type'] == null ? 'word' : idText(j['type']).toLowerCase(),
    isRequired: j['required'] == true,
    values: [for (final v in (j['values'] as List? ?? const [])) idText(v)],
    isRest: j['rest'] == true,
    max: j['max'] is num ? (j['max'] as num).toInt() : null,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'required': isRequired,
    if (values.isNotEmpty) 'values': values,
    if (isRest) 'rest': true,
    'max': ?max,
  };
}

/// A group of the catalogue (`categories`).
class CommandCategory {
  const CommandCategory(this.id, this.label);

  final String id;
  final String label;
}

/// One `#command` of the server's catalog, or one of the person's own custom
/// commands (`cmd.list`).
class HashCommand {
  const HashCommand({
    required this.name,
    this.aliases = const [],
    this.category = '',
    this.summary = '',
    this.usage = '',
    this.args = const [],
    this.replies = const [],
    this.isAvailable = true,
    this.requires = 'none',
    this.isCustom = false,
    this.isLocal = false,
  });

  final String name;
  final List<String> aliases;
  final String category;
  final String summary;
  final String usage;
  final List<String> replies;
  final bool isAvailable;
  final String requires;
  final bool isCustom;

  /// Opens an app screen; never sent to the server.
  final bool isLocal;

  final List<CommandArg> args;

  bool answersTo(String word) => name == word || aliases.contains(word);

  bool startsWithPrefix(String prefix) =>
      name.startsWith(prefix) || aliases.any((a) => a.startsWith(prefix));

  factory HashCommand.fromJson(
    Map<String, dynamic> j, {
    bool isCustom = false,
  }) => HashCommand(
    name: idText(j['name']).toLowerCase(),
    aliases: [
      for (final a in (j['aliases'] as List? ?? const []))
        idText(a).toLowerCase(),
    ],
    category: isCustom ? 'custom' : idText(j['category']),
    summary: idText(j['summary']),
    usage: idText(j['usage']),
    args: [
      for (final a in (j['args'] as List? ?? const []))
        if (a is Map) CommandArg.fromJson(a.cast<String, dynamic>()),
    ],
    replies: [for (final r in (j['reply'] as List? ?? const [])) idText(r)],
    isAvailable: j['available'] is bool ? j['available'] as bool : true,
    requires: j['requires'] == null ? 'none' : idText(j['requires']),
    isCustom: isCustom,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'aliases': aliases,
    'category': category,
    'summary': summary,
    'usage': usage,
    'args': [for (final a in args) a.toJson()],
    'reply': replies,
    'available': isAvailable,
    'requires': requires,
    'custom': isCustom,
  };
}
