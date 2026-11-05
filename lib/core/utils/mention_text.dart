/// The one parser of `@name` tags (bubbles, quotes, the reply bar), with the web's rule
/// (`messageFormat.js`): an `@` at the start or after anything but a letter,
/// digit, `@`, `.`, `_` or `-`, then 2 to 24 characters of `A-Za-z0-9._-`
/// starting with a letter or digit, trailing `.`, `_`, `-` left out.
class MentionText {
  MentionText._();

  static final _at = RegExp(r'^@([A-Za-z0-9][A-Za-z0-9._-]{1,23})');
  static final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final _stop = RegExp(r'[@._-]');
  static final _trail = RegExp(r'[._-]+$');

  /// Cuts [text] into runs. A run with [MentionRun.user] set is a tag (the
  /// name lower-cased); the rest is plain text. Joining every run's [text]
  /// gives [text] back.
  static List<MentionRun> split(String text) {
    final runs = <MentionRun>[];
    var plainFrom = 0;
    var i = 0;
    while (i < text.length) {
      if (text[i] == '@' && _isTagStart(text, i)) {
        final end = i + 26 > text.length ? text.length : i + 26;
        final m = _at.firstMatch(text.substring(i, end));
        final name = m?.group(1)?.replaceFirst(_trail, '');
        if (name != null && name.length >= 2) {
          if (i > plainFrom) runs.add(MentionRun(text.substring(plainFrom, i)));
          runs.add(
            MentionRun(
              text.substring(i, i + 1 + name.length),
              user: name.toLowerCase(),
            ),
          );
          i += 1 + name.length;
          plainFrom = i;
          continue;
        }
      }
      i++;
    }
    if (plainFrom < text.length) {
      runs.add(MentionRun(text.substring(plainFrom)));
    }
    return runs;
  }

  static bool _isTagStart(String text, int i) {
    if (i == 0) return true;
    final prev = text[i - 1];
    return !(_word.hasMatch(prev) || _stop.hasMatch(prev));
  }
}

class MentionRun {
  const MentionRun(this.text, {this.user});

  final String text;
  final String? user;
}

/// The people whose @tags are drawn as a name: [names] maps a lower-case
/// username to the name shown after the `@`. Anyone not in it is drawn as
/// typed. I am always known.
class MentionPeople {
  const MentionPeople({required this.me, this.names = const {}});

  final String me;
  final Map<String, String> names;

  bool isKnown(String user) => user == me || names.containsKey(user);

  bool isMe(String user) => user == me;

  /// The display name, or the username when the person has none.
  String nameOf(String user) {
    final name = names[user];
    return name == null || name.trim().isEmpty ? user : name;
  }
}
