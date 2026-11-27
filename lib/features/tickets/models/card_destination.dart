import '../../../core/routes/app_routes.dart';
import 'package:connectum/data/models/models.dart';
import 'record_card_rule.dart';
import 'record_history_card.dart';

/// Where a tap on a form or record card leads: the one decision between the
/// record screen (details, history, actions) and the submission detail. A
/// record card is what [RecordCardRule] says (the rule that shows its
/// actions); a record's history card opens the record in its own "Record"
/// field; anything else is a plain submission. Nothing depends on the
/// `record` summary, which may be absent.
class CardDestination {
  CardDestination._();

  /// Null when a history card names no record: nothing opens.
  static String? of(FormCardData d, {String? convId, String? msgId}) {
    if (RecordHistoryCard.isCard(d)) {
      final record = RecordHistoryCard.recordIdOf(d);
      return record == null ? null : AppRoutes.ticketOf(record);
    }
    final id = RecordCardRule.of(d).id;
    if (id != null) return AppRoutes.ticketOf(id);
    return AppRoutes.submissionDetailOf(d.id, convId: convId, msgId: msgId);
  }
}
