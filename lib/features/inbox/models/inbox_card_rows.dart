import 'package:connectum/core/utils/utils.dart';
import '../../../data/smart_view/sv_file.dart';
import 'inbox_field_kind.dart';
import 'inbox_row.dart';

/// One line of a card body: a name, the value as text, what it is about (the
/// icon) and, for a field of files, the files (only ids, until the server
/// sends names, types and sizes in `fileMeta`).
class InboxCardRow {
  const InboxCardRow({
    required this.name,
    required this.value,
    this.kind = InboxFieldKind.other,
    this.files = const [],
    this.hasFileInfo = false,
  });

  final String name;
  final String value;
  final InboxFieldKind kind;
  final List<SvFile> files;

  /// The server sent the details of these files (names, types, sizes): they
  /// show as chips. Without it only "n files" shows, never a raw id.
  final bool hasFileInfo;

  bool get hasFiles => files.isNotEmpty;

  /// A row made from plain text (an approval's lines): the kind comes from the
  /// name and the shape of the value.
  factory InboxCardRow.plain(String name, String value) {
    final kind = InboxFieldKind.of(name: name, key: '', raw: value);
    return InboxCardRow(
      name: name,
      value: dateText(value) ?? value,
      kind: kind,
    );
  }

  /// "3 files" / "1 file".
  static String filesText(int n) => n == 1 ? '1 file' : '$n files';

  /// An ISO date written as the app writes dates ("16 Nov 2026"); null when
  /// [v] is not one.
  static String? dateText(String v) {
    final d = InboxFieldKind.isoDate(v);
    if (d == null) return null;
    final ts = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
    final hasTime = v.trim().length > 10;
    return hasTime
        ? '${ChatTime.date(ts)}, ${ChatTime.time(d.millisecondsSinceEpoch)}'
        : ChatTime.date(ts);
  }
}

String _text(Object? v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  if (v is bool) return v ? 'Yes' : 'No';
  if (v is num) {
    return v is double && v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toString();
  }
  if (v is List) {
    return [for (final e in v) _text(e)].where((s) => s.isNotEmpty).join(', ');
  }
  return '';
}

/// The lines of a card body (`recordRows.js`): every answer in the order the
/// reply gave them, a choice by its label, the status left out (the band
/// shows it), empty answers dropped, the external id last. [typeOf] gives a
/// field's type when the structure is known (never read from the server for
/// this). A list of file ids becomes files, an ISO date the app's date.
List<InboxCardRow> inboxCardRows(
  InboxRow row, {
  String? Function(String field)? typeOf,
}) {
  final rows = <InboxCardRow>[];
  for (final e in row.values.entries) {
    if (e.key == row.statusField) continue;
    final caption = row.fields[e.key];
    final name = caption == null || caption.isEmpty ? e.key : caption;
    final type = typeOf?.call(e.key);
    if (InboxFieldKind.isFileIdList(e.value)) {
      final info = row.files[e.key];
      final files = SvFile.listOf(e.value, info);
      if (files.isNotEmpty) {
        rows.add(
          InboxCardRow(
            name: name,
            value: InboxCardRow.filesText(files.length),
            kind: InboxFieldKind.file,
            files: files,
            hasFileInfo: info is List,
          ),
        );
        continue;
      }
    }
    final raw = row.labels[e.key] ?? e.value;
    final text = _text(raw);
    if (text.isEmpty) continue;
    rows.add(
      InboxCardRow(
        name: name,
        value: InboxCardRow.dateText(text) ?? text,
        kind: InboxFieldKind.of(
          name: name,
          key: e.key,
          raw: row.labels[e.key] == null ? e.value : text,
          type: type,
        ),
      ),
    );
  }
  if (row.externalId.isNotEmpty) {
    rows.add(
      InboxCardRow(
        name: 'External ID',
        value: row.externalId,
        kind: InboxFieldKind.number,
      ),
    );
  }
  return rows;
}
