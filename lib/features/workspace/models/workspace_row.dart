import '../../../data/models/form_card.dart';
import 'workspace_note.dart';

/// One row of the workspace feed: a submission card, a note, or a day label.
class WorkspaceRow {
  const WorkspaceRow.card(FormCardData this.card)
    : label = '',
      note = null,
      isReceived = false;

  /// A record someone sent to me (`records.mine`), keyed `rec-<id>` like the
  /// web's.
  const WorkspaceRow.received(FormCardData this.card)
    : label = '',
      note = null,
      isReceived = true;

  const WorkspaceRow.note(WorkspaceNote this.note)
    : label = '',
      card = null,
      isReceived = false;

  const WorkspaceRow.day(this.label)
    : card = null,
      note = null,
      isReceived = false;

  final FormCardData? card;
  final WorkspaceNote? note;
  final String label;
  final bool isReceived;

  String get key => card != null
      ? '${isReceived ? 'rec' : 'c'}-${card!.id}'
      : note != null
      ? 'n-${note!.id}'
      : 'd-$label';
}
