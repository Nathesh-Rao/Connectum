/// One row of the "@" list.
class MentionPerson {
  const MentionPerson({required this.username, this.name = ''});

  final String username;
  final String name;

  /// The name shown; the username when the person has none.
  String get label => name.trim().isEmpty ? username : name;
}

/// The "@" typed at the caret: where it starts and what follows it.
class MentionQuery {
  const MentionQuery(this.start, this.query);

  final int start;
  final String query;
}

/// The "@" list of a group's message box, with the web's rules
/// (`mentionPicker.js`). Pure: no UI, no state.
class MentionPicker {
  MentionPicker._();

  static const maxRows = 6;
  static const maxQuery = 24;
  static const _openers = ' \n\t([{"\'';

  /// The tag being typed at [caret], or null. The `@` must be the first
  /// character or follow a space, a line break or one of `( [ { " '`; from it
  /// to the caret there is no space and at most 24 characters.
  static MentionQuery? detect(String text, int caret) {
    if (caret < 0 || caret > text.length) return null;
    final floor = caret - maxQuery - 1 < 0 ? 0 : caret - maxQuery - 1;
    for (var i = caret - 1; i >= floor; i--) {
      final c = text[i];
      if (c == ' ' || c == '\n' || c == '\t' || c == '\r') return null;
      if (c != '@') continue;
      if (i > 0 && !_openers.contains(text[i - 1])) return null;
      return MentionQuery(i, text.substring(i + 1, caret));
    }
    return null;
  }

  /// The people that match [query], never [me], each once: rank 0 the
  /// username or whole name starts with it, rank 1 a word of the name does,
  /// rank 2 either contains it; by name inside a rank; at most [maxRows].
  static List<MentionPerson> filter(
    Iterable<MentionPerson> people,
    String query, {
    required String me,
  }) {
    final q = query.toLowerCase();
    final seen = <String>{me.toLowerCase()};
    final ranked = <(int, String, MentionPerson)>[];
    for (final p in people) {
      final user = p.username.toLowerCase();
      if (!seen.add(user)) continue;
      final name = p.label.toLowerCase();
      final rank = q.isEmpty ? 0 : _rank(user, name, q);
      if (rank != null) ranked.add((rank, name, p));
    }
    ranked.sort((a, b) {
      final byRank = a.$1.compareTo(b.$1);
      return byRank != 0 ? byRank : a.$2.compareTo(b.$2);
    });
    return [for (final r in ranked.take(maxRows)) r.$3];
  }

  static int? _rank(String user, String name, String q) {
    if (user.startsWith(q) || name.startsWith(q)) return 0;
    if (name.split(RegExp(r'\s+')).any((w) => w.startsWith(q))) return 1;
    if (user.contains(q) || name.contains(q)) return 2;
    return null;
  }

  /// [text] with the typed `@query` (up to [caret]) replaced by `@username`
  /// and one space, unless a space already follows; the caret after it.
  static ({String text, int caret}) insert(
    String text,
    MentionQuery at,
    int caret,
    String username,
  ) {
    final before = text.substring(0, at.start);
    final after = text.substring(caret);
    final hasSpace = after.startsWith(' ');
    final tag = '@${username.toLowerCase()}';
    return (
      text: '$before$tag${hasSpace ? '' : ' '}$after',
      caret: before.length + tag.length + 1,
    );
  }
}
