import '../../../data/models/form_card.dart';
import 'workspace_note.dart';

/// One row of the workspace feed: a submission card, a note, or a day label.
class WorkspaceRow {
  const WorkspaceRow.card(FormCardData this.card) : label = '', note = null;

  const WorkspaceRow.note(WorkspaceNote this.note) : label = '', card = null;

  const WorkspaceRow.day(this.label) : card = null, note = null;

  final FormCardData? card;
  final WorkspaceNote? note;
  final String label;

  String get key => card != null
      ? 'c-${card!.id}'
      : note != null
      ? 'n-${note!.id}'
      : 'd-$label';
}
