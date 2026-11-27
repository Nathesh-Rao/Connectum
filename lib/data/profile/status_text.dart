/// The status message rules. The server answers `invalid_status` for text over
/// 140 characters; it counts the characters of its decoded string, so this
/// counts Unicode code points (runes): an emoji is one, a flag or a family
/// emoji is several, exactly as the server's `length/1` sees them. The web
/// counts UTF-16 units instead and cuts an emoji at the boundary.
class StatusText {
  StatusText._();

  static const maxLength = 140;
  static const warnFrom = 130;

  static final _control = RegExp(r'[\u0000-\u001F\u007F]');

  /// Removes control characters (and so newlines and tabs).
  static String clean(String text) => text.replaceAll(_control, '');

  /// The number of characters the server counts.
  static int length(String text) => text.runes.length;

  /// [text] cut to [maxLength] code points, never inside a pair.
  static String cut(String text) {
    final runes = text.runes;
    if (runes.length <= maxLength) return text;
    return String.fromCharCodes(runes.take(maxLength));
  }

  /// What is typed, cleaned and cut.
  static String typed(String text) => cut(clean(text));

  /// What is sent: cleaned, cut and trimmed. Empty clears the status.
  static String toSend(String text) => cut(clean(text)).trim();
}
