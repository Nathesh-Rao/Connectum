import 'inbox_row.dart';

/// One name and value line of a card body.
typedef InboxCardRow = (String name, String value);

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
/// shows it), empty answers dropped, the external id last.
List<InboxCardRow> inboxCardRows(InboxRow row) {
  final rows = <InboxCardRow>[];
  for (final e in row.values.entries) {
    if (e.key == row.statusField) continue;
    final value = _text(row.labels[e.key] ?? e.value);
    if (value.isEmpty) continue;
    final caption = row.fields[e.key];
    rows.add((caption == null || caption.isEmpty ? e.key : caption, value));
  }
  if (row.externalId.isNotEmpty) rows.add(('External ID', row.externalId));
  return rows;
}
