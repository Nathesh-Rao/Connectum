/// The one owner of how a summary reads when posted into a chat as an ordinary
/// text message.
class AiSummaryMessageFormat {
  AiSummaryMessageFormat._();

  static const title = '✨ AI summary';

  /// The server refuses longer text (`mobile-handoff/messages-and-receipts.md`).
  static const maxLength = 2000;

  /// More parts than this would flood the chat: the rest is cut instead.
  static const maxParts = 5;

  static const shortened = '…(shortened)';

  /// Keeps `@name` from being read as a mention (the server and the app both
  /// need a letter or digit right after the `@`).
  static const _guard = '​';

  static final _mention = RegExp(
    r'(?<![\p{L}\p{N}@._-])@(?=[A-Za-z0-9])',
    unicode: true,
  );

  /// The messages to post, in order: one when it fits, else numbered parts
  /// "(1/2)", each with its own title line. The first line is exactly
  /// [title] (section 7 of the BE follow-up doc).
  static List<String> build(String text) {
    final body = text.trim().replaceAllMapped(_mention, (m) => '@$_guard');
    const head = title;
    final whole = '$head\n\n$body';
    if (whole.length <= maxLength) return [whole];
    // Room for " (99/99)" after the title and the blank line.
    final budget = maxLength - head.length - ' (99/99)'.length - 2;
    final chunks = <String>[];
    var rest = body;
    while (rest.isNotEmpty) {
      if (chunks.length == maxParts - 1 && rest.length > budget) {
        chunks.add(_cut(rest, budget - shortened.length) + shortened);
        break;
      }
      if (rest.length <= budget) {
        chunks.add(rest);
        break;
      }
      final cut = _breakAt(rest, budget);
      chunks.add(rest.substring(0, cut).trimRight());
      rest = rest.substring(cut).trimLeft();
    }
    final n = chunks.length;
    return [for (var i = 0; i < n; i++) '$head (${i + 1}/$n)\n\n${chunks[i]}'];
  }

  static String _cut(String s, int max) =>
      s.substring(0, _breakAt(s, max)).trimRight();

  /// Where to cut [s] so the first piece is at most [max] long: after a
  /// paragraph, a line, a sentence or a word, in that order, else hard.
  static int _breakAt(String s, int max) {
    final window = s.substring(0, max);
    for (final mark in ['\n\n', '\n', '. ', '! ', '? ', ' ']) {
      final i = window.lastIndexOf(mark);
      if (i > max ~/ 3) return i + (mark.trim().isEmpty ? 0 : 1);
    }
    final isSplitPair =
        window.codeUnitAt(max - 1) >= 0xD800 &&
        window.codeUnitAt(max - 1) <= 0xDBFF;
    return isSplitPair ? max - 1 : max;
  }
}
