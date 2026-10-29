import '../../../data/models/form_card.dart';
import '../../../data/models/form_entry.dart';

/// One submission in the list: its card data plus what the list needs to
/// filter and search it.
class SubmissionRow {
  SubmissionRow(this.card)
    : preview = card.cardEntries.take(3).toList(),
      searchText = [
        card.caption,
        card.id,
        card.status ?? '',
        for (final e in card.cardEntries) e.text,
      ].join(' ').toLowerCase();

  final FormCardData card;

  /// The first few values, for the row.
  final List<FormEntry> preview;
  final String searchText;
}
