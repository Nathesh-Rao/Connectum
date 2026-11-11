import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/features/chat_info/chat_info_controller.dart';
import 'package:connectum/features/chat_info/models/chat_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Conversations extends Fake implements ConversationRepository {
  @override
  final conversations = <Conversation>[].obs;
}

class _Tickets extends Fake implements TicketRepository {
  Ticket? ticket;
  int reads = 0;

  @override
  String get me => 'ana';

  @override
  bool isMe(String user) => user.toLowerCase() == 'ana';

  @override
  String nameOf(String user) => user == 'ana' ? 'Ana Lopez' : user;

  @override
  Ticket? known(int id) => ticket;

  @override
  ({Ticket ticket, bool isAdmin, bool? inPool})? stateOf(int id) =>
      ticket == null ? null : (ticket: ticket!, isAdmin: false, inPool: null);

  @override
  Future<void> ensure(int id) async => reads++;
}

class _Store extends Fake implements SessionStore {
  @override
  String? get userId => 'ana';
}

class _Connectivity extends Fake implements ConnectivityService {
  @override
  final state = AppConnectivity.online.obs;
}

void main() {
  late _Conversations conversations;
  late _Tickets tickets;

  ChatInfoController make(String id, {bool isEncrypted = false}) =>
      ChatInfoController(
        conversationId: id,
        isEncryptedHint: isEncrypted,
        conversations: conversations,
        tickets: tickets,
        store: _Store(),
        connectivity: _Connectivity(),
      );

  setUp(() {
    conversations = _Conversations();
    tickets = _Tickets();
  });

  test('a conversation that is not stored has no data', () {
    expect(make('group:nope').data, isNull);
  });

  test('a group I own: members, owner row and add people', () {
    conversations.conversations.add(
      const Conversation(
        convId: 'group:design',
        kind: 'group',
        title: 'Design',
        members: ['ana', 'bob'],
        memberCount: 2,
        owner: 'Ana',
      ),
    );
    final d = make('group:design').data!;
    expect(d.kind, ChatInfoKind.group);
    expect(d.subtitle, '2 members');
    expect(d.canAddPeople, isTrue);
    expect(d.members.first.name, 'Ana Lopez');
    expect(d.members.first.isMe, isTrue);
    expect([for (final r in d.rows) r.value], ['Group', 'You']);
    expect(d.isEncrypted, isFalse);
    expect(tickets.reads, 0);
  });

  test('the conversation screen can say the chat is encrypted', () {
    conversations.conversations.add(
      const Conversation(convId: 'dm:bob', kind: 'dm', title: 'Bob'),
    );
    final d = make('dm:bob', isEncrypted: true).data!;
    expect(d.kind, ChatInfoKind.personal);
    expect(d.isEncrypted, isTrue);
    expect(d.subtitle, '@bob');
    expect(d.members, isEmpty);
    expect(d.canAddPeople, isFalse);
  });

  test('a record conversation reads the ticket once and shows its summary', () {
    conversations.conversations.add(
      const Conversation(
        convId: 'group:rec-help_ticket-5',
        kind: 'group',
        title: 'Printer',
        members: ['ana', 'bob'],
        memberCount: 2,
        canRename: true,
      ),
    );
    final c = make('group:rec-help_ticket-5')..onInit();
    expect(tickets.reads, 1);
    // Not read yet: a thread with a spinner.
    var d = c.data!;
    expect(d.kind, ChatInfoKind.thread);
    expect(d.canRename, isTrue);
    tickets.ticket = Ticket(
      id: 5,
      by: 'bob',
      ts: 0,
      tstruct: 'help_ticket',
      values: const {
        'status': 'Open',
        'title': 'Printer',
        'assigned to': 'ana',
      },
      form: const TicketForm(
        key: 'help_ticket',
        caption: 'Help ticket',
        table: TicketTable(
          field: 'status',
          assignee: 'assigned to',
          subject: 'title',
          statuses: [TicketStatus('Open')],
        ),
      ),
    );
    d = c.data!;
    expect(d.kind, ChatInfoKind.ticket);
    expect(d.subtitle, 'Ticket #5');
    expect(d.ticketRows.map((r) => r.value), contains('You'));
    expect(c.ticketId, 5);
  });

  test('a plain group has no ticket to read', () {
    conversations.conversations.add(
      const Conversation(convId: 'group:design', kind: 'group', title: 'D'),
    );
    final c = make('group:design')..onInit();
    expect(c.ticketId, isNull);
    expect(tickets.reads, 0);
    expect(c.data!.hasMembersGap, isTrue);
  });
}
