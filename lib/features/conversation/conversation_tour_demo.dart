import 'package:get/get.dart';

import '../../core/selection/message_selection.dart';
import '../../core/selection/selection_rules.dart';
import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/data/models/models.dart';
import 'conversation_tour.dart';
import 'models/chat_item.dart';
import 'models/forward.dart';

/// The sample thread of the chat tour, shown only when the chat has no
/// message of its own. It is plain in-memory state that the conversation view
/// reads while [isOn]; it holds no repository, database, socket or outbox, so
/// nothing sample can be saved, sent, counted or marked read. Its selection is
/// a separate [MessageSelection] that the real controller never sees.
class ConversationTourDemo {
  static const incomingId = 'tour-sample-in';
  static const ownId = 'tour-sample-out';
  static const convId = 'tour-sample';

  /// True while the sample is shown.
  final isOn = false.obs;

  /// The sample's own selection (one message at most, set by the tour).
  final selection = MessageSelection();

  /// Newest first, like the thread's own list.
  List<ChatItem> items = const [];

  ConversationTourCaps caps = const ConversationTourCaps();
  bool hasRealMessage = false;

  /// What the tour will show, read when the tour starts.
  void prepare(ConversationTourCaps caps, {required bool hasRealMessage}) {
    this.caps = caps;
    this.hasRealMessage = hasRealMessage;
  }

  /// Puts the two sample messages in. False when real messages exist.
  bool seed() {
    if (hasRealMessage) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final incoming = Message(
      msgId: incomingId,
      convId: convId,
      sender: TourTexts.sampleSender,
      isMine: false,
      text: TourTexts.sampleWelcome,
      ts: now - const Duration(minutes: 2).inMilliseconds,
      status: MessageStatus.sent,
    );
    final own = Message(
      msgId: ownId,
      convId: convId,
      sender: 'me',
      isMine: true,
      text: TourTexts.sampleReply,
      ts: now - const Duration(minutes: 1).inMilliseconds,
      status: MessageStatus.sent,
    );
    final showName = !caps.isDirect;
    items = [
      ChatItem.message(own, isFirstOfRun: true, isLastOfRun: true),
      ChatItem.message(
        incoming,
        isFirstOfRun: true,
        isLastOfRun: true,
        showName: showName,
      ),
    ];
    isOn.value = true;
    return true;
  }

  /// Takes the sample out and clears its selection. Safe to call again.
  void restore() {
    selection.clear();
    isOn.value = false;
    items = const [];
  }

  /// The sample messages that are selected now.
  List<Message> get selectedMessages => [
    for (final i in items)
      if (i.message != null && selection.isSelected(i.message!.msgId))
        i.message!,
  ];

  /// Selects the sample message that has edit and delete (the user's own).
  void select() {
    if (!isOn.value) return;
    if (!selection.isSelected(ownId)) selection.ids.add(ownId);
    selection.isBarHidden.value = false;
  }

  void clearSelection() => selection.clear();

  /// What the sample own message allows, from what the chat allows. The
  /// real thread decides the same with the controller's `targetOf`.
  static SelectionTarget targetOf(ConversationTourCaps caps) {
    final probe = Message(
      msgId: ownId,
      convId: convId,
      sender: 'me',
      isMine: true,
      text: TourTexts.sampleReply,
      ts: 0,
      status: MessageStatus.sent,
    );
    return SelectionTarget(
      id: ownId,
      canReply: caps.canReply,
      canForward: Forward.canForward(probe),
      canCopy: true,
      canDelete: caps.canDelete,
      canEdit: caps.canEdit && !caps.isEncrypted,
      canReact: caps.canReact,
    );
  }
}
