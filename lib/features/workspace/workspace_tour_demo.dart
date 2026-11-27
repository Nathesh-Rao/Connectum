import 'package:get/get.dart';

import '../../core/selection/message_selection.dart';
import '../../core/selection/selection_rules.dart';
import '../../core/tour/tour_texts.dart';
import '../../data/models/message.dart';
import '../../data/models/self_conversation.dart';

/// The sample note of the My Work Space tour, shown only when the screen has
/// no note of its own. Plain in-memory state that the view reads while [isOn]:
/// no repository, database, socket or outbox, so it cannot be saved, sent,
/// pinned or counted. Its selection is separate from the screen's.
class WorkspaceTourDemo {
  static const noteId = 'tour-sample-note';

  final isOn = false.obs;
  final selection = MessageSelection();

  Message? note;
  bool hasRealNote = false;

  void prepare({required bool hasRealNote}) => this.hasRealNote = hasRealNote;

  /// Puts the sample note in. False when the screen has a note of its own.
  bool seed() {
    if (hasRealNote) return false;
    note = Message(
      msgId: noteId,
      convId: SelfConversation.id,
      sender: 'me',
      isMine: true,
      text: TourTexts.sampleNote,
      ts: DateTime.now().millisecondsSinceEpoch,
      status: MessageStatus.sent,
    );
    isOn.value = true;
    return true;
  }

  /// Takes the sample out and clears its selection. Safe to call again.
  void restore() {
    selection.clear();
    isOn.value = false;
    note = null;
  }

  void select() {
    if (!isOn.value) return;
    if (!selection.isSelected(noteId)) selection.ids.add(noteId);
    selection.isBarHidden.value = false;
  }

  void clearSelection() => selection.clear();

  /// The notes the sample bar is built for (the note, while it is selected).
  List<Message> get selectedNotes {
    final n = note;
    return n != null && selection.isSelected(n.msgId) ? [n] : const [];
  }

  /// What a sent note of mine allows in the selection bar.
  static const target = SelectionTarget(
    id: noteId,
    canReply: true,
    canStar: true,
    canPin: true,
    canEdit: true,
    canCopy: true,
    canDelete: true,
  );
}
