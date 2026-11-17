import 'models/sv_row.dart';
import 'models/sv_source.dart';
import 'sv_card_content.dart';
import 'sv_cell_format.dart';

enum SvColType {
  text,
  number,
  date,
  time,
  datetime,
  status,
  select,
  checkbox,
  email,
  phone,
  url,
  file,
  unknown,
}

/// One display column: the record meta the web table shows (No., By,
/// Submitted, Status) or one of the structure's own fields.
class SvColumn {
  const SvColumn({
    required this.key,
    required this.label,
    required this.type,
    this.isMeta = false,
    this.isKey = false,
  });

  final String key;
  final String label;
  final SvColType type;
  final bool isMeta;
  final bool isKey;
}

/// A cell: the text to show (never null; [SmartViewColumns.empty] when blank)
/// and the value as the row holds it.
class SvCellValue {
  const SvCellValue(this.text, this.typed);

  final String text;
  final Object? typed;

  bool get isEmpty => text == SmartViewColumns.empty;
}

/// What a card prints for one record.
class SvCardData {
  const SvCardData({
    required this.title,
    required this.status,
    required this.ticketStatus,
    required this.number,
    required this.by,
    required this.submitted,
    required this.fields,
  });

  final String title;

  /// The record's own state word (`Recorded`, `Waiting for approval`, ...).
  final String status;

  /// The value of the structure's status field; empty when it has none.
  final String ticketStatus;
  final String number;
  final String by;
  final String submitted;
  final List<({SvColumn column, SvCellValue cell})> fields;
}

/// The single source of what Cards and Table show: ordered columns from a
/// structure's field list and cell text from [SvCell]. A hidden field is not
/// in the source list, so it is never a column and its value is never read.
/// Unknown field types are shown as safe raw text.
class SmartViewColumns {
  SmartViewColumns._(this.source, this.columns);

  /// What a blank value shows (the text of [SvCell.dash] in the design).
  static const empty = '—';

  static const noKey = '#no';
  static const byKey = '#by';
  static const submittedKey = '#submitted';
  static const statusKey = '#status';

  final SvSource source;
  final List<SvColumn> columns;

  static SmartViewColumns of(SvSource source) {
    final statusField = source.table?.field;
    SvColumn own(SvField f) => SvColumn(
      key: f.name,
      label: f.caption,
      type: f.name == statusField ? SvColType.status : typeOf(f.type),
      isKey: f.name == source.keyField,
    );
    final fields = [
      for (final f in source.fields)
        if (!source.gridSections.contains(f.section)) f,
    ];
    final key = [
      for (final f in fields)
        if (f.name == source.keyField) f,
    ];
    final ticket = [
      for (final f in fields)
        if (f.name == statusField && f.name != source.keyField) f,
    ];
    final rest = [
      for (final f in fields)
        if (f.name != source.keyField && f.name != statusField) f,
    ];
    return SmartViewColumns._(source, [
      const SvColumn(
        key: noKey,
        label: 'No.',
        type: SvColType.number,
        isMeta: true,
      ),
      for (final f in key) own(f),
      const SvColumn(
        key: byKey,
        label: 'By',
        type: SvColType.text,
        isMeta: true,
      ),
      const SvColumn(
        key: submittedKey,
        label: 'Submitted',
        type: SvColType.datetime,
        isMeta: true,
      ),
      const SvColumn(
        key: statusKey,
        label: 'Status',
        type: SvColType.status,
        isMeta: true,
      ),
      for (final f in ticket) own(f),
      for (final f in rest) own(f),
    ]);
  }

  /// The field types the app knows how to print; anything else is
  /// [SvColType.unknown] and printed as raw text.
  static SvColType typeOf(String type) => switch (type) {
    'text' || 'location' || 'payment' => SvColType.text,
    'number' || 'wholenumber' => SvColType.number,
    'date' || 'slot' => SvColType.date,
    'time' => SvColType.time,
    'datetime' => SvColType.datetime,
    'status' => SvColType.status,
    'selection' || 'list' || 'people' => SvColType.select,
    'toggle' => SvColType.checkbox,
    'email' => SvColType.email,
    'phone' => SvColType.phone,
    'url' => SvColType.url,
    'file' => SvColType.file,
    _ => SvColType.unknown,
  };

  List<SvColumn> get ownColumns => [
    for (final c in columns)
      if (!c.isMeta) c,
  ];

  List<SvColumn> get metaColumns => [
    for (final c in columns)
      if (c.isMeta) c,
  ];

  SvCellValue cellOf(SvColumn column, SvRow row) {
    switch (column.key) {
      case noKey:
        return SvCellValue('${row.id}', row.id);
      case byKey:
        final by = row.byName.isNotEmpty ? row.byName : row.by;
        return SvCellValue(by.isEmpty ? empty : by, by);
      case submittedKey:
        return SvCellValue(_shown(SvCell.stamp(row.ts)), row.ts);
      case statusKey:
        return SvCellValue(row.approval, row.recordStatus);
    }
    final f = source.fieldOf(column.key);
    if (f == null) return const SvCellValue(empty, null);
    final raw = row.values[f.name];
    return SvCellValue(
      _shown(SvCell.of(f, raw, labels: row.labels, files: row.files)),
      raw,
    );
  }

  /// Every cell of [row], in column order.
  List<SvCellValue> cellsOf(SvRow row) => [
    for (final c in columns) cellOf(c, row),
  ];

  SvCardData cardOf(SvRow row) {
    final c = SvCardContent.of(source, row);
    final statusField = source.table?.field;
    final fields = <({SvColumn column, SvCellValue cell})>[];
    for (final col in ownColumns) {
      if (col.key == statusField ||
          col.key == source.keyField ||
          col.key == c.titleField) {
        continue;
      }
      fields.add((column: col, cell: cellOf(col, row)));
    }
    final ticket = statusField == null
        ? ''
        : SvCell.of(
            source.fieldOf(statusField),
            row.values[statusField],
            labels: row.labels,
          );
    return SvCardData(
      title: c.title,
      status: row.approval,
      ticketStatus: ticket == SvCell.dash ? '' : ticket,
      number: c.number,
      by: c.by.isEmpty ? empty : c.by,
      submitted: _shown(c.submitted),
      fields: fields,
    );
  }

  static String _shown(String text) => text == SvCell.dash ? empty : text;
}
