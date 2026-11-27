import '../../models/form_definition.dart';
import '../../models/ids.dart';
import '../../models/ticket.dart';

/// One field of a source as the source list gives it. A hidden field is not
/// in the list, so nothing that is not here is ever drawn.
class SvField {
  const SvField({
    required this.name,
    required this.caption,
    this.type = 'text',
    this.section,
    this.isRich = false,
  });

  final String name;
  final String caption;
  final String type;
  final String? section;
  final bool isRich;

  static SvField? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = idText(raw['name']);
    if (name.isEmpty) return null;
    final caption = idText(raw['caption']);
    return SvField(
      name: name,
      caption: caption.isEmpty ? name : caption,
      type: idText(raw['type']).isEmpty || FormFieldDef.isAutoFillMap(raw)
          ? 'text'
          : idText(raw['type']),
      section: raw['section'] == null ? null : idText(raw['section']),
      isRich: raw['rich'] == true,
    );
  }
}

/// A structure that can be opened as a table (`ai.enterprise` `forms[]`).
class SvSource {
  const SvSource({
    required this.name,
    required this.caption,
    this.keyField,
    this.owner = '',
    this.isSystem = false,
    this.canFetch = true,
    this.canAdd = true,
    this.creatorCanDelete = true,
    this.hasThread = false,
    this.table,
    this.fields = const [],
    this.gridSections = const {},
  });

  final String name;
  final String caption;
  final String? keyField;
  final String owner;

  /// A built-in structure; the person's own come first.
  final bool isSystem;
  final bool canFetch;
  final bool canAdd;

  /// False when the form turned off the author's Delete (only [owner] may).
  final bool creatorCanDelete;
  final bool hasThread;
  final TicketTable? table;
  final List<SvField> fields;

  /// Names of the sections that are grids (one column for all their rows).
  final Set<String> gridSections;

  bool get hasStatus => table != null;

  SvField? fieldOf(String name) {
    for (final f in fields) {
      if (f.name == name) return f;
    }
    return null;
  }

  /// The form the record screens know this structure by.
  TicketForm get form => TicketForm(
    key: name,
    caption: caption,
    fields: {for (final f in fields) f.name: f.caption},
    hasThread: hasThread,
    table: table,
  );

  /// "your structure" / "built-in structure".
  String get hint => isSystem ? 'built-in structure' : 'your structure';

  static SvSource? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = idText(raw['name']);
    if (name.isEmpty) return null;
    final caption = idText(raw['caption']);
    final sections = raw['sections'];
    return SvSource(
      name: name,
      caption: caption.isEmpty ? name : caption,
      keyField: raw['keyField'] == null || idText(raw['keyField']).isEmpty
          ? null
          : idText(raw['keyField']),
      owner: idText(raw['owner']),
      isSystem: raw['system'] == true,
      canFetch: raw['canFetch'] != false,
      canAdd: raw['canAdd'] != false,
      creatorCanDelete: raw['creatorCanDelete'] != false,
      hasThread: raw['recordThread'] == true,
      table: TicketTable.tryParse(raw['status']),
      fields: [
        if (raw['fields'] is List)
          for (final f in raw['fields'] as List) ?SvField.tryParse(f),
      ],
      gridSections: {
        if (sections is List)
          for (final s in sections)
            if (s is Map && s['grid'] == true) idText(s['name']),
      },
    );
  }
}

/// The matching and suggestion rules of the web's `#view` (`findSource`,
/// `Composer.jsx`), for structures only.
class SvSources {
  SvSources._();

  /// The picker's order: the person's own first, then caption A to Z.
  static List<SvSource> sorted(Iterable<SvSource> all) {
    final list = [
      for (final s in all)
        if (s.canFetch) s,
    ];
    list.sort((a, b) {
      if (a.isSystem != b.isSystem) return a.isSystem ? 1 : -1;
      return a.caption.toLowerCase().compareTo(b.caption.toLowerCase());
    });
    return list;
  }

  /// The source a typed name opens: name or caption equal (case-insensitive),
  /// else the first whose name or caption contains it.
  static SvSource? find(List<SvSource> all, String typed) {
    final q = typed.trim().toLowerCase();
    if (q.isEmpty) return null;
    final usable = [
      for (final s in all)
        if (s.canFetch) s,
    ];
    for (final s in usable) {
      if (s.name.toLowerCase() == q || s.caption.toLowerCase() == q) return s;
    }
    for (final s in usable) {
      if (s.name.toLowerCase().contains(q) ||
          s.caption.toLowerCase().contains(q)) {
        return s;
      }
    }
    return null;
  }

  /// The composer menu after `#view `: sources whose name or caption contains
  /// [typed]; those that start with it first, then the person's own before
  /// built-in, then the list's own order; at most 30. Exactly one left that
  /// equals the typed text: none, so Enter runs it.
  static List<SvSource> suggest(List<SvSource> all, String typed) {
    final q = typed.trim().toLowerCase();
    final hits = <(int, SvSource)>[];
    for (var i = 0; i < all.length; i++) {
      final s = all[i];
      if (!s.canFetch) continue;
      final n = s.name.toLowerCase();
      final c = s.caption.toLowerCase();
      if (q.isNotEmpty && !n.contains(q) && !c.contains(q)) continue;
      hits.add((i, s));
    }
    int starts(SvSource s) =>
        q.isNotEmpty &&
            (s.name.toLowerCase().startsWith(q) ||
                s.caption.toLowerCase().startsWith(q))
        ? 0
        : 1;
    hits.sort((a, b) {
      final s = starts(a.$2).compareTo(starts(b.$2));
      if (s != 0) return s;
      if (a.$2.isSystem != b.$2.isSystem) return a.$2.isSystem ? 1 : -1;
      return a.$1.compareTo(b.$1);
    });
    final out = [for (final h in hits.take(30)) h.$2];
    if (out.length == 1 && out.first.name.toLowerCase() == q) {
      return const [];
    }
    return out;
  }
}
