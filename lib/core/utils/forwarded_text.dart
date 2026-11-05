/// A forwarded message is an ordinary message whose text starts with
/// `↪ [Forwarded by <name> • from <author>]: <text>`. This reads the line
/// back, as the web does (`chatMessages.js`).
class ForwardedText {
  const ForwardedText({
    required this.isForwarded,
    required this.text,
    this.forwardedBy,
    this.originalFrom,
  });

  static final _line = RegExp(
    r'^↪\s*\[Forwarded(?:\s+by\s+([^•\]]+))?(?:\s*•\s*from\s+([^\]]+))?\]:\s*([\s\S]*)$',
    caseSensitive: false,
  );

  final bool isForwarded;

  /// The text without the forward line.
  final String text;

  /// The forwarder, or [parse]'s sender when the line has no name.
  final String? forwardedBy;

  /// The original author, when the line names one.
  final String? originalFrom;

  /// [sender] stands in for a forwarder the line does not name.
  static ForwardedText parse(String text, {String sender = ''}) {
    final m = _line.firstMatch(text);
    if (m == null) return ForwardedText(isForwarded: false, text: text);
    final by = m.group(1)?.trim() ?? '';
    final from = m.group(2)?.trim() ?? '';
    return ForwardedText(
      isForwarded: true,
      text: m.group(3) ?? '',
      forwardedBy: by.isEmpty ? sender : by,
      originalFrom: from.isEmpty ? null : from,
    );
  }
}
