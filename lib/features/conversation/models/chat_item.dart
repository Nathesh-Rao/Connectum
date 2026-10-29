import '../../../data/models/message.dart';

enum ChatItemKind { message, day, unread, loadingOlder, olderError, start }

/// One row of the conversation list: a message, or a divider or status row
/// between messages. Built from the cached messages, newest first.
class ChatItem {
  const ChatItem.message(
    Message this.message, {
    this.isFirstOfRun = true,
    this.isLastOfRun = true,
    this.showName = false,
    this.isFresh = false,
  }) : kind = ChatItemKind.message,
       label = '';

  const ChatItem.day(this.label)
    : kind = ChatItemKind.day,
      message = null,
      isFirstOfRun = true,
      isLastOfRun = true,
      showName = false,
      isFresh = false;

  const ChatItem.unread(this.label)
    : kind = ChatItemKind.unread,
      message = null,
      isFirstOfRun = true,
      isLastOfRun = true,
      showName = false,
      isFresh = false;

  const ChatItem.status(this.kind)
    : message = null,
      label = '',
      isFirstOfRun = true,
      isLastOfRun = true,
      showName = false,
      isFresh = false;

  final ChatItemKind kind;
  final Message? message;
  final String label;

  /// First and last message of a run from the same sender: the tail sits on
  /// the last one, a received name above the first.
  final bool isFirstOfRun;
  final bool isLastOfRun;
  final bool showName;

  /// Arrived live while the list was at the bottom: enters with a rise.
  final bool isFresh;

  String get key => switch (kind) {
    ChatItemKind.message => 'm-${message!.cid ?? message!.msgId}',
    ChatItemKind.day => 'd-$label',
    ChatItemKind.unread => 'unread',
    _ => kind.name,
  };
}
