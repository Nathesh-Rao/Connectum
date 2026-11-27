import 'package:connectum/data/models/models.dart';
import 'workspace_note.dart';

/// One row of the workspace feed: a submission card, a small row that is not
/// stored, a stored note of mine (a message), or a day label.
class WorkspaceRow {
  const WorkspaceRow.card(FormCardData this.card)
    : label = '',
      note = null,
      message = null,
      isReceived = false;

  /// A record someone sent to me (`records.mine`), keyed `rec-<id>` like the
  /// web's.
  const WorkspaceRow.received(FormCardData this.card)
    : label = '',
      note = null,
      message = null,
      isReceived = true;

  const WorkspaceRow.note(WorkspaceNote this.note)
    : label = '',
      card = null,
      message = null,
      isReceived = false;

  /// A note of mine kept on the server and in SQLite.
  const WorkspaceRow.message(Message this.message)
    : label = '',
      card = null,
      note = null,
      isReceived = false;

  const WorkspaceRow.day(this.label)
    : card = null,
      note = null,
      message = null,
      isReceived = false;

  final FormCardData? card;
  final WorkspaceNote? note;
  final Message? message;
  final String label;
  final bool isReceived;

  String get key => card != null
      ? '${isReceived ? 'rec' : 'c'}-${card!.id}'
      : note != null
      ? 'n-${note!.id}'
      : message != null
      ? 'm-${message!.msgId}'
      : 'd-$label';
}
