import 'models/sv_row.dart';
import 'models/sv_source.dart';
import 'sv_cell_format.dart';

/// What one record card prints, from the web's default column order (key
/// field, No., By, Submitted, Approval, status field, With, Progress, own
/// fields). The status, who it is with and the progress are the status
/// block's; the card adds up to [ownFields] of the structure's own fields.
/// A key that is not in the source list (a hidden field) is never read.
class SvCardContent {
  const SvCardContent({
    required this.title,
    required this.number,
    required this.by,
    required this.submitted,
    required this.approval,
    required this.pairs,
    this.titleField,
  });

  /// The web's phone card shows six columns; the BE recommends more, so the
  /// card shows the first three own fields too.
  static const ownFields = 3;

  final String title;
  final String number;
  final String by;
  final String submitted;

  /// Empty for a record that is simply recorded.
  final String approval;
  final List<({String label, String value})> pairs;

  /// The field the title was read from; null for the `<caption> #<id>` text.
  final String? titleField;

  static SvCardContent of(SvSource source, SvRow row) {
    final statusField = source.table?.field;
    String text(SvField f) =>
        SvCell.of(f, row.values[f.name], labels: row.labels, files: row.files);

    final key = source.keyField == null
        ? null
        : source.fieldOf(source.keyField!);
    var title = key == null ? SvCell.dash : text(key);
    String? titleName = title == SvCell.dash ? null : key?.name;
    if (title == SvCell.dash) {
      for (final f in source.fields) {
        if (f.name == statusField || f.type == 'file') continue;
        final t = text(f);
        if (t != SvCell.dash) {
          title = t;
          titleName = f.name;
          break;
        }
      }
    }
    if (title == SvCell.dash) title = '${source.caption} #${row.id}';

    bool isShown(SvField f) =>
        f.name != statusField &&
        f.name != source.keyField &&
        f.name != titleName &&
        !source.gridSections.contains(f.section);
    final own = [
      for (final f in source.fields)
        if (isShown(f)) f,
    ].take(ownFields);
    final approval = row.approval;
    return SvCardContent(
      title: title,
      number: '${row.id}',
      by: row.byName.isNotEmpty ? row.byName : row.by,
      submitted: SvCell.stamp(row.ts),
      approval: approval == 'Recorded' ? '' : approval,
      pairs: [for (final f in own) (label: f.caption, value: text(f))],
      titleField: titleName,
    );
  }
}
