import 'dart:convert';

import 'ids.dart';

/// One emoji under a message: how many people used it and whether I did.
class Reaction {
  const Reaction({
    required this.emoji,
    required this.count,
    required this.isMine,
  });

  /// The quick row of the long-press sheet, then the ones the "+" adds.
  static const quick = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
  static const more = ['🔥', '🎉', '👏', '💯', '🚀', '✨', '🤝', '🥰', '🤩', '👀'];

  final String emoji;
  final int count;
  final bool isMine;

  /// The stored `[{user, emoji}]` grouped by emoji, oldest first (the server
  /// lists the newest first). A bad or empty value gives an empty list.
  static List<Reaction> parse(String? json, String me) {
    if (json == null || json.isEmpty || json == '[]') return const [];
    final Object? data;
    try {
      data = jsonDecode(json);
    } on FormatException {
      return const [];
    }
    if (data is! List) return const [];
    final counts = <String, int>{};
    final mine = <String>{};
    for (final item in data.reversed) {
      if (item is! Map) continue;
      final emoji = idText(item['emoji']);
      if (emoji.isEmpty) continue;
      counts[emoji] = (counts[emoji] ?? 0) + 1;
      if (idText(item['user']).toLowerCase() == me) mine.add(emoji);
    }
    return [
      for (final e in counts.entries)
        Reaction(emoji: e.key, count: e.value, isMine: mine.contains(e.key)),
    ];
  }
}
