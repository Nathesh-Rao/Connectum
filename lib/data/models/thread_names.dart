import 'ids.dart';

/// `record.names`: the titles of the record conversations I am in, which of
/// them I may rename and which their form keeps out of the main list. Keys are
/// group names (`rec-ticket-12`).
class RecordNames {
  const RecordNames({
    this.names = const {},
    this.canRename = const {},
    this.hidden = const {},
  });

  final Map<String, String> names;
  final Set<String> canRename;
  final Set<String> hidden;

  factory RecordNames.fromReply(Map<String, dynamic> data) => RecordNames(
    names: _textMap(data['names']),
    canRename: _textSet(data['canRename']),
    hidden: _textSet(data['hidden']),
  );
}

/// `care.names` ({names: {username: full name}}) and `org.name` ({name}): what
/// a person's shared thread (`care-<username>`) is titled.
class CareNames {
  const CareNames._();

  /// Lower-case username -> full name; empty names are left out.
  static Map<String, String> fromReply(Map<String, dynamic> data) => {
    for (final e in _textMap(data['names']).entries)
      e.key.toLowerCase(): e.value,
  };

  /// The organisation's own name, empty when the reply has none.
  static String orgFromReply(Map<String, dynamic> data) =>
      idText(data['name']).trim();
}

/// `record.rename` reply: {id, title}, the title now shown to everyone.
class RecordRename {
  const RecordRename({required this.id, required this.title});

  final int id;
  final String title;

  /// The server's own limit: "A name can be at most 60 characters."
  static const maxLength = 60;
  static const tooLong = 'A name can be at most 60 characters.';

  /// Null when the name is fine; an empty name is fine (it brings the made
  /// title back).
  static String? problemWith(String name) =>
      name.trim().runes.length > maxLength ? tooLong : null;

  factory RecordRename.fromReply(Map<String, dynamic> data) =>
      RecordRename(id: intOf(data['id']), title: idText(data['title']));
}

Map<String, String> _textMap(Object? raw) => raw is Map
    ? {
        for (final e in raw.entries)
          if (idText(e.value).isNotEmpty) idText(e.key): idText(e.value),
      }
    : const {};

Set<String> _textSet(Object? raw) =>
    raw is List ? {for (final g in raw) idText(g)} : const {};
