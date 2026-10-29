import '../../../data/models/form_card.dart';

/// One row of the workspace feed: a submission card, or a day label.
class WorkspaceRow {
  const WorkspaceRow.card(FormCardData this.card) : label = '';

  const WorkspaceRow.day(this.label) : card = null;

  final FormCardData? card;
  final String label;

  String get key => card != null ? 'c-${card!.id}' : 'd-$label';
}
