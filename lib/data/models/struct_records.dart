import '../smart_view/models/sv_row.dart';
import '../smart_view/models/sv_source.dart';
import '../smart_view/sv_cell_format.dart';
import 'form_definition.dart';
import 'ids.dart';

/// A structure as the records screen draws it: the fields a person may see
/// (a hidden field is left out unless the person made the structure or is an
/// administrator, as on the web) and what the structure allows.
class StructRecordsSchema {
  const StructRecordsSchema({
    required this.name,
    required this.scope,
    required this.caption,
    required this.source,
    required this.isReadOnly,
  });

  final String name;
  final String scope;
  final String caption;
  final SvSource source;

  /// One of the organisation's own lists, or the history of every record:
  /// kept by Connectum, so no New record, Edit or Delete.
  final bool isReadOnly;

  static StructRecordsSchema of(
    FormDefinition def, {
    required bool isCreator,
    required bool isAdmin,
  }) {
    final raw = def.raw;
    final seesHidden = isCreator || isAdmin;
    final system = idText(raw['system']);
    final fields = raw['fields'];
    final source = SvSource.tryParse({
      ...raw,
      'name': def.name,
      'caption': def.caption,
      'fields': [
        if (fields is List)
          for (final f in fields)
            if (f is Map && (seesHidden || f['hidden'] != true)) f,
      ],
    });
    return StructRecordsSchema(
      name: def.name,
      scope: def.scope,
      caption: def.caption.isEmpty ? def.name : def.caption,
      source: source ?? SvSource(name: def.name, caption: def.name),
      isReadOnly:
          (system.isNotEmpty && system != 'access') ||
          raw['recordHistory'] == true,
    );
  }
}

/// One page of the structure's records, newest first.
class StructRecordsPage {
  const StructRecordsPage({
    required this.rows,
    required this.total,
    required this.hasMore,
    required this.received,
  });

  final List<SvRow> rows;
  final int total;
  final bool hasMore;

  /// How many records the server sent (the next offset moves by this).
  final int received;
}

/// What a record card prints: the key field (else the first filled field)
/// as the title, "No. 12", and up to [ownFields] more fields. A file field
/// is only a count; a hidden field is not in the source, so never read.
class StructRecordCardData {
  const StructRecordCardData({
    required this.id,
    required this.title,
    required this.pairs,
    required this.approval,
    required this.by,
  });

  static const ownFields = 4;

  final int id;
  final String title;
  final List<({String label, String value})> pairs;

  /// `Waiting for approval` or `Declined`; empty for a record.
  final String approval;
  final String by;

  static String _text(SvField f, SvRow row) {
    if (f.type != 'file') {
      return SvCell.of(f, row.values[f.name], labels: row.labels);
    }
    final v = row.values[f.name];
    final n = v is List ? v.length : 0;
    return n == 0
        ? SvCell.dash
        : n == 1
        ? '1 file'
        : '$n files';
  }

  static StructRecordCardData of(SvSource source, SvRow row) {
    final key = source.keyField == null
        ? null
        : source.fieldOf(source.keyField!);
    var title = key == null ? SvCell.dash : _text(key, row);
    String? titleName = title == SvCell.dash ? null : key?.name;
    if (title == SvCell.dash) {
      for (final f in source.fields) {
        if (f.type == 'file' || source.gridSections.contains(f.section)) {
          continue;
        }
        final t = _text(f, row);
        if (t != SvCell.dash) {
          title = t;
          titleName = f.name;
          break;
        }
      }
    }
    if (title == SvCell.dash) title = source.caption;
    final own = [
      for (final f in source.fields)
        if (f.name != titleName &&
            !source.gridSections.contains(f.section) &&
            _text(f, row) != SvCell.dash)
          f,
    ].take(ownFields);
    return StructRecordCardData(
      id: row.id,
      title: title,
      pairs: [for (final f in own) (label: f.caption, value: _text(f, row))],
      approval: switch (row.recordStatus.toLowerCase()) {
        'pending' => 'Waiting for approval',
        'rejected' => 'Declined',
        _ => '',
      },
      by: row.byName.isNotEmpty ? row.byName : row.by,
    );
  }
}
