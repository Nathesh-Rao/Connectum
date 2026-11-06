/// The two kinds of shared thread, told from a group's name the way the web
/// does: `care-<username>` (a person's) and `rec-<structure>-<number>` (a
/// record's own conversation).
class ChatThread {
  ChatThread._();

  static final _care = RegExp(r'^care-[A-Za-z0-9._-]+$');
  static final _record = RegExp(r'^rec-(.+)-(\d+)$', caseSensitive: false);

  /// The group name of a conversation id (`group:rec-ticket-12`), null for a
  /// direct, host or global one.
  static String? groupName(String convId) =>
      convId.startsWith('group:') ? convId.substring(6) : null;

  static bool isThreadName(String name) {
    final n = name.trim();
    return _care.hasMatch(n) || _record.hasMatch(n);
  }

  static bool isRecordName(String name) => _record.hasMatch(name.trim());

  /// The username of a care thread (`care-ana.lopez`), null for any other name.
  static String? careUser(String name) {
    final n = name.trim();
    return _care.hasMatch(n) ? n.substring(5) : null;
  }

  /// The record number of a record conversation (`rec-ticket-12` is 12).
  static int? recordId(String name) {
    final rec = _record.firstMatch(name.trim());
    return rec == null ? null : int.tryParse(rec.group(2)!);
  }

  /// What is shown until the server's title is known: "rec-ticket-12" is
  /// "Ticket #12", "care-ana.lopez" is "Ana Lopez"; any other name is kept.
  static String fallbackTitle(String name) {
    final n = name.trim();
    final rec = _record.firstMatch(n);
    if (rec != null) return '${_tidy(rec.group(1)!)} #${rec.group(2)}';
    if (_care.hasMatch(n)) return _tidy(n.substring(5));
    return name;
  }

  static String _tidy(String s) => s
      .replaceAll(RegExp(r'[._-]+'), ' ')
      .replaceAllMapped(RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());
}
