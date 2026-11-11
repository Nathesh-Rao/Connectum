import '../../../data/models/chat_thread.dart';
import '../../../data/models/conversation.dart';
import '../../../data/models/ticket.dart';
import '../../chats/widgets/conversation_tile.dart';
import '../../tickets/models/ticket_detail_row.dart';
import '../../tickets/tickets_texts.dart';

enum ChatInfoKind { personal, group, thread, ticket }

/// One person in the member list.
class ChatInfoMember {
  const ChatInfoMember({
    required this.user,
    required this.name,
    this.isMe = false,
    this.isOwner = false,
  });

  final String user;
  final String name;
  final bool isMe;
  final bool isOwner;

  String get handle => '@$user';

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        name.toLowerCase().contains(q) ||
        user.toLowerCase().contains(q);
  }

  /// Owner first, then by name.
  static List<ChatInfoMember> listOf(
    Conversation c, {
    required String me,
    required String Function(String user) nameOf,
  }) {
    final owner = c.owner.toLowerCase();
    final list = [
      for (final user in c.members)
        ChatInfoMember(
          user: user,
          name: nameOf(user),
          isMe: user.toLowerCase() == me.toLowerCase(),
          isOwner: owner.isNotEmpty && user.toLowerCase() == owner,
        ),
    ];
    list.sort((a, b) {
      if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }
}

/// Everything the info page shows, worked out from what is stored. The page
/// only draws it.
class ChatInfoData {
  const ChatInfoData({
    required this.kind,
    required this.conversation,
    required this.subtitle,
    this.isEncrypted = false,
    this.rows = const [],
    this.members = const [],
    this.hasMembersGap = false,
    this.ticket,
    this.ticketRows = const [],
    this.isTicketLoading = false,
    this.hasTicketGap = false,
    this.canRename = false,
    this.canAddPeople = false,
  });

  /// More than this many members: a search field shows above the list.
  static const searchThreshold = 15;

  final ChatInfoKind kind;
  final Conversation conversation;
  final String subtitle;
  final bool isEncrypted;

  /// Icon-chip rows under the header (not the ticket's).
  final List<TicketDetailRow> rows;
  final List<ChatInfoMember> members;

  /// A group whose member list is not stored yet.
  final bool hasMembersGap;
  final Ticket? ticket;
  final List<TicketDetailRow> ticketRows;
  final bool isTicketLoading;

  /// A record conversation whose ticket could not be read and is not cached.
  final bool hasTicketGap;
  final bool canRename;
  final bool canAddPeople;

  String get title => conversation.title;
  bool get hasSearch => members.length > searchThreshold;
  bool get hasMembers => kind != ChatInfoKind.personal;

  static ChatInfoKind kindOf(Conversation c, {bool isTicket = false}) {
    if (c.kind == 'dm') return ChatInfoKind.personal;
    final name = ChatThread.groupName(c.convId);
    if (name != null && ChatThread.isRecordName(name)) {
      return isTicket ? ChatInfoKind.ticket : ChatInfoKind.thread;
    }
    if (name != null && ChatThread.careUser(name) != null) {
      return ChatInfoKind.thread;
    }
    return ChatInfoKind.group;
  }

  static String typeLabelOf(Conversation c, ChatInfoKind kind) =>
      kind == ChatInfoKind.thread
      ? 'Thread'
      : ConversationTile.typeLabel(c.kind);

  static String subtitleOf(
    Conversation c,
    ChatInfoKind kind, {
    Ticket? ticket,
    int? ticketId,
  }) {
    switch (kind) {
      case ChatInfoKind.personal:
        return '@${c.peer ?? ''}';
      case ChatInfoKind.ticket:
        return '${TicketsTexts.ticketMarker} #${ticket?.id ?? ticketId}';
      case ChatInfoKind.group || ChatInfoKind.thread:
        return c.memberCount > 0
            ? '${c.memberCount} members'
            : typeLabelOf(c, kind);
    }
  }
}
