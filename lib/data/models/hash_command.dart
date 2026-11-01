import 'ids.dart';

/// One `#command` of the server's catalog, or one of the person's own custom
/// commands (`cmd.list`).
class HashCommand {
  const HashCommand({
    required this.name,
    this.aliases = const [],
    this.category = '',
    this.summary = '',
    this.usage = '',
    this.replies = const [],
    this.isAvailable = true,
    this.requires = 'none',
    this.isCustom = false,
  });

  /// Reply events that mean the command put a message into a chat.
  static const _messageReplies = {
    'dm_ack',
    'group_msg_ack',
    'host_ack',
    'own_message_id',
  };

  /// The commands the backend rewrites into a message send (chat_cmds.erl),
  /// kept here too so a catalog that omits `reply` cannot hide one.
  static const _messageNames = {
    'dm',
    'reply',
    'replydm',
    'groupmsg',
    'replygroup',
  };

  final String name;
  final List<String> aliases;
  final String category;
  final String summary;
  final String usage;
  final List<String> replies;
  final bool isAvailable;
  final String requires;
  final bool isCustom;

  bool get sendsMessage =>
      !isCustom &&
      (_messageNames.contains(name) || replies.any(_messageReplies.contains));

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
    'reply': replies,
    'available': isAvailable,
    'requires': requires,
    'custom': isCustom,
  };
}
