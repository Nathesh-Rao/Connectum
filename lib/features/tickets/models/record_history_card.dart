import '../../../data/models/form_card.dart';
import '../../../data/models/ids.dart';

/// The read-only form message a record's conversation gets for each event
/// (`structure: "record_history"`). Its `submissionId` is the history row,
/// NOT the record: it is never used to open anything. The record is the
/// card's own "Record" field.
class RecordHistoryCard {
  RecordHistoryCard._();

  static const structure = 'record_history';

  static bool isCard(FormCardData d) => d.structure == structure;

  /// The record this event belongs to, from the card's "Record" field; null
  /// when the card has none.
  static int? recordIdOf(FormCardData d) {
    for (final e in d.entries) {
      if (e.name.toLowerCase() == 'record' ||
          e.caption.toLowerCase() == 'record') {
        final id = idNumber(e.text.replaceAll('#', '').trim());
        if (id != null) return id;
      }
    }
    return null;
  }
}
