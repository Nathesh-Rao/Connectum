import 'package:connectum/data/models/models.dart';
import 'record_history_card.dart';

/// The web's rule for a record card (`formToCard`): a form message whose form
/// carries a numeric `submissionId`, is not read-only and is not a
/// data-source result. Nothing about its status or menu: that is
/// `record.actions`, read when the menu or the record opens.
class RecordCardRule {
  const RecordCardRule._(this.id, this.rule);

  /// The record's id; null for a plain form card.
  final int? id;

  /// Why, for the `[records]` decision line.
  final String rule;

  bool get isRecord => id != null;

  static const recordRule = 'numeric submissionId, not read-only, no result';

  static RecordCardRule of(FormCardData d) {
    if (d.isPending)
      return const RecordCardRule._(null, 'pending, no record id');
    if (RecordHistoryCard.isCard(d)) {
      return const RecordCardRule._(null, 'record_history card, read-only');
    }
    if (d.isReadOnly) {
      return const RecordCardRule._(null, 'read-only form');
    }
    if (d.hasResult) {
      return const RecordCardRule._(null, 'data-source result');
    }
    final id = idNumber(d.id);
    if (id == null) {
      return const RecordCardRule._(null, 'no numeric submissionId');
    }
    return RecordCardRule._(id, recordRule);
  }
}
