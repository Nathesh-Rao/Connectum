import '../../../data/models/chat_thread.dart';
import '../../../data/models/conversation.dart';

/// The chips of the Chats list, in the order of the web.
enum ChatFilterKind { all, direct, threads }

/// Which conversations a chip lists, with the web's rules
/// (WorkspaceChatsSlider.jsx): Direct & Teams is everything but hosts, Threads
/// is the shared threads (`care-<user>`, `rec-<structure>-<n>`), and a record
/// conversation its form keeps out of the main list shows under Threads only.
class ChatFilter {
  ChatFilter._();

  static bool isThread(Conversation c) {
    final name = ChatThread.groupName(c.convId);
    return name != null && ChatThread.isThreadName(name);
  }

  /// The web lists the General Broadcast room in no chip. Set this to true to
  /// show it in All again, once it has had a message.
  static const showGeneralBroadcast = false;

  /// Archived conversations are never listed, and the global room only when
  /// [showGeneralBroadcast] is on and it has had a message.
  static bool isListed(Conversation c) =>
      !c.isArchived &&
      (c.kind != 'global' || (showGeneralBroadcast && c.lastTs > 0));

  static bool matches(ChatFilterKind filter, Conversation c) {
    switch (filter) {
      case ChatFilterKind.threads:
        return isThread(c);
      case ChatFilterKind.direct:
        return !c.isListHidden && c.kind != 'host' && c.kind != 'global';
      case ChatFilterKind.all:
        return !c.isListHidden;
    }
  }

  /// Case-insensitive text in the title or the last text; an empty query
  /// matches everything.
  static bool matchesQuery(String query, Conversation c) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return c.title.toLowerCase().contains(q) ||
        c.lastText.toLowerCase().contains(q);
  }

  /// The listed conversations of one chip, searched and in list order: pinned
  /// first, then newest.
  static List<Conversation> apply(
    List<Conversation> all,
    ChatFilterKind filter, {
    String query = '',
  }) =>
      all
          .where(
            (c) => isListed(c) && matches(filter, c) && matchesQuery(query, c),
          )
          .toList()
        ..sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return b.lastTs.compareTo(a.lastTs);
        });

  /// The Threads chip exists only while some thread conversation does, an
  /// archived one included.
  static bool hasThreads(List<Conversation> all) => all.any(isThread);

  /// What the Threads chip counts: the unread of every thread conversation,
  /// muted and archived ones included.
  static int threadUnread(List<Conversation> all) =>
      all.where(isThread).fold(0, (n, c) => n + c.unread);
}
