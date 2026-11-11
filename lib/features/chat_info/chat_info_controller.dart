import 'dart:async';

import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/conversation_route.dart';
import '../../data/models/chat_thread.dart';
import '../../data/models/conversation.dart';
import '../../data/models/ticket.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import '../chats/record_rename_controller.dart';
import '../tickets/models/ticket_detail_row.dart';
import '../tickets/models/ticket_rows.dart';
import 'models/chat_info.dart';

/// The info page of one conversation. It reads what is already stored (the
/// conversation row and its member list) and, for a record conversation, the
/// ticket through the same short cache the chat cards use: nothing is asked
/// of the server on every open, and a pull reads the ticket again.
class ChatInfoController extends GetxController {
  ChatInfoController({
    required this.conversationId,
    required this.isEncryptedHint,
    required this.conversations,
    required this.tickets,
    required this.store,
    required this.connectivity,
  });

  final String conversationId;

  /// What the conversation screen already knows (a chat with encrypted
  /// history is encrypted even when the stored flag is not set yet).
  final bool isEncryptedHint;
  final ConversationRepository conversations;
  final TicketRepository tickets;
  final SessionStore store;
  final ConnectivityService connectivity;

  final isTicketLoading = false.obs;
  final hasTicketGap = false.obs;

  String get me => (store.userId ?? '').toLowerCase();

  Conversation? get conversation {
    final rows = SeedUi.isActive
        ? SeedUi.conversations()
        : conversations.conversations;
    for (final c in rows) {
      if (c.convId == conversationId) return c;
    }
    return null;
  }

  /// The ticket number of a record conversation (`rec-ticket-12`), else null.
  int? get ticketId {
    final name = ChatThread.groupName(conversationId);
    return name == null ? null : ChatThread.recordId(name);
  }

  @override
  void onInit() {
    super.onInit();
    if (ticketId != null) unawaited(_readTicket());
  }

  Future<void> _readTicket() async {
    final id = ticketId!;
    isTicketLoading.value = tickets.known(id) == null;
    await tickets.ensure(id);
    isTicketLoading.value = false;
    hasTicketGap.value = tickets.known(id) == null;
  }

  /// Pull to refresh: the ticket is read again whatever the cache says.
  Future<void> refreshTicket() async {
    final id = ticketId;
    if (id == null) return;
    try {
      await tickets.get(id);
      hasTicketGap.value = false;
    } on SocketCallError {
      hasTicketGap.value = tickets.known(id) == null;
    }
  }

  /// Reads Rx values (the conversation list, the ticket revision): call it
  /// inside an Obx. Null when the conversation is not stored.
  ChatInfoData? get data {
    final c = conversation;
    if (c == null) return null;
    final id = ticketId;
    final Ticket? ticket = id == null ? null : tickets.stateOf(id)?.ticket;
    final kind = ChatInfoData.kindOf(c, isTicket: ticket?.isTicket ?? false);
    final isGroupLike = kind != ChatInfoKind.personal;
    final members = isGroupLike
        ? ChatInfoMember.listOf(c, me: me, nameOf: tickets.nameOf)
        : const <ChatInfoMember>[];
    final owner = c.owner;
    return ChatInfoData(
      kind: kind,
      conversation: c,
      subtitle: ChatInfoData.subtitleOf(c, kind, ticket: ticket, ticketId: id),
      isEncrypted: isEncryptedHint || c.isEncrypted,
      rows: switch (kind) {
        ChatInfoKind.personal => [TicketDetailRow.of('Username', c.peer ?? '')],
        ChatInfoKind.ticket => const [],
        _ => [
          TicketDetailRow.of('Type', ChatInfoData.typeLabelOf(c, kind)),
          if (owner.isNotEmpty)
            TicketDetailRow.of(
              'Owner',
              owner.toLowerCase() == me ? 'You' : tickets.nameOf(owner),
            ),
        ],
      },
      members: members,
      hasMembersGap: isGroupLike && c.kind == 'group' && c.members.isEmpty,
      ticket: kind == ChatInfoKind.ticket ? ticket : null,
      ticketRows: kind == ChatInfoKind.ticket && ticket != null
          ? ticketSummaryRows(
              ticket,
              assignedTo: tickets.isMe(ticket.withWhom)
                  ? 'You'
                  : tickets.nameOf(ticket.withWhom),
            )
          : const [],
      isTicketLoading: id != null && ticket == null && isTicketLoading.value,
      hasTicketGap: id != null && ticket == null && hasTicketGap.value,
      canRename: c.canRename && id != null,
      canAddPeople:
          c.kind == 'group' &&
          owner.toLowerCase() == me &&
          store.userId != null,
    );
  }

  RecordRenameController? get renamer {
    final c = conversation;
    if (c == null) return null;
    return RecordRenameController(
      onRename: (name) => conversations.renameRecord(c, name),
      isOffline: () => connectivity.state.value == AppConnectivity.offline,
    );
  }

  void openTicket() {
    final id = ticketId;
    if (id != null) Get.toNamed<void>(AppRoutes.ticketOf(id));
  }

  void addPeople() => Get.toNamed<void>(
    AppRoutes.newGroup,
    arguments: ConversationRepository.targetOf(conversationId),
  );

  /// A person's own chat. Nothing for me.
  void openMember(ChatInfoMember member) {
    if (member.isMe) return;
    ConversationRoute.open('dm:${member.user.toLowerCase()}');
  }
}
