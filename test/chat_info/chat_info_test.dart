import 'package:connectum/core/widgets/app_avatar.dart';
import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/features/chat_info/models/chat_info.dart';
import 'package:connectum/features/chat_info/widgets/chat_info_body.dart';
import 'package:connectum/features/tickets/models/ticket_detail_row.dart';
import 'package:connectum/features/tickets/models/ticket_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _conv(
  String id,
  String kind,
  String title, {
  int members = 0,
  String owner = '',
  bool canRename = false,
}) {
  final users = [for (var i = 0; i < members; i++) 'user$i'];
  return Conversation(
    convId: id,
    kind: kind,
    title: title,
    members: users,
    memberCount: users.length,
    owner: owner,
    canRename: canRename,
  );
}

List<ChatInfoMember> _members(Conversation c, {String me = 'user1'}) =>
    ChatInfoMember.listOf(c, me: me, nameOf: (u) => 'Name $u');

Ticket get _ticket => Ticket(
  id: 217,
  by: 'user0',
  ts: 0,
  tstruct: 'help_ticket',
  values: const {
    'ticket no': 'T-217',
    'title': 'Printer is jammed',
    'category': 'Hardware',
    'subtype': 'Printer',
    'priority': 'High',
    'need by': '2026-11-12',
    'expected completion': '2026-11-10',
    'assigned to': 'user2',
    'status': 'In progress',
    'completion': 40,
    'notes': 'Not in the summary',
  },
  form: const TicketForm(
    key: 'help_ticket',
    caption: 'Help ticket',
    fields: {
      'ticket no': 'Ticket no',
      'title': 'Title',
      'category': 'Category',
      'subtype': 'Subtype',
      'priority': 'Priority',
      'need by': 'Need by',
      'expected completion': 'Expected completion',
      'assigned to': 'Assigned to',
      'status': 'Status',
      'completion': 'Completion',
      'notes': 'Notes',
    },
    table: TicketTable(
      field: 'status',
      assignee: 'assigned to',
      completion: 'completion',
      subject: 'title',
      statuses: [TicketStatus('Open'), TicketStatus('In progress')],
    ),
  ),
);

Widget _host(ChatInfoData data, {Map<String, int>? taps, double? width}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: ChatInfoBody(
            data: data,
            onOpenTicket: () => taps?['ticket'] = (taps['ticket'] ?? 0) + 1,
            onRename: () => taps?['rename'] = (taps['rename'] ?? 0) + 1,
            onAddPeople: () => taps?['add'] = (taps['add'] ?? 0) + 1,
            onOpenMember: (m) => taps?[m.user] = (taps[m.user] ?? 0) + 1,
          ),
        ),
      ),
    );

ChatInfoData _group(int members, {bool isEncrypted = false}) {
  final c = _conv(
    'group:design team',
    'group',
    'Design Team',
    members: members,
    owner: 'user0',
  );
  return ChatInfoData(
    kind: ChatInfoKind.group,
    conversation: c,
    subtitle: '$members members',
    isEncrypted: isEncrypted,
    rows: [
      TicketDetailRow.of('Type', 'Group'),
      TicketDetailRow.of('Owner', 'Name user0'),
    ],
    members: _members(c),
  );
}

void main() {
  group('kind and words', () {
    test('kind comes from the conversation id and the ticket', () {
      ChatInfoKind kind(String id, String k, {bool isTicket = false}) =>
          ChatInfoData.kindOf(_conv(id, k, 'x'), isTicket: isTicket);
      expect(kind('dm:ana', 'dm'), ChatInfoKind.personal);
      expect(kind('group:design', 'group'), ChatInfoKind.group);
      expect(kind('host:Billing', 'host'), ChatInfoKind.group);
      expect(kind('group:care-ana', 'group'), ChatInfoKind.thread);
      expect(kind('group:rec-help_ticket-3', 'group'), ChatInfoKind.thread);
      expect(
        kind('group:rec-help_ticket-3', 'group', isTicket: true),
        ChatInfoKind.ticket,
      );
    });

    test('subtitles', () {
      final g = _conv('group:g', 'group', 'G', members: 2);
      expect(ChatInfoData.subtitleOf(g, ChatInfoKind.group), '2 members');
      expect(
        ChatInfoData.subtitleOf(
          _conv('group:g', 'group', 'G'),
          ChatInfoKind.group,
        ),
        'Group',
      );
      expect(
        ChatInfoData.subtitleOf(
          _conv('dm:ana', 'dm', 'Ana'),
          ChatInfoKind.personal,
        ),
        '@ana',
      );
      expect(
        ChatInfoData.subtitleOf(g, ChatInfoKind.ticket, ticket: _ticket),
        'Ticket #217',
      );
    });

    test('members: owner first, then by name; me and owner marked', () {
      final c = _conv('group:g', 'group', 'G', members: 4, owner: 'user3');
      final list = _members(c, me: 'USER1');
      expect(list.first.user, 'user3');
      expect(list.first.isOwner, isTrue);
      expect(list.where((m) => m.isMe).single.user, 'user1');
      expect(
        [for (final m in list.skip(1)) m.user],
        ['user0', 'user1', 'user2'],
      );
      expect(list.first.handle, '@user3');
      expect(list.first.matches('NAME USER3'), isTrue);
      expect(list.first.matches('zzz'), isFalse);
      expect(list.first.matches('user3'), isTrue);
    });

    test('the ticket summary: the listed rows in order, nothing else', () {
      final rows = ticketSummaryRows(_ticket, assignedTo: 'Chen Wei');
      expect(
        [for (final r in rows) r.label],
        [
          'Ticket no',
          'Priority',
          'Assigned to',
          'Category',
          'Subtype',
          'Need by',
          'Expected completion',
        ],
      );
      expect(rows[1].priority, isNotNull);
      expect(rows[2].value, 'Chen Wei');
      expect(rows[5].value, '12 Nov 2026');
    });
  });

  group('the page', () {
    testWidgets('group: header, rows, members, owner and you markers', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_group(5, isEncrypted: true)));
      expect(find.text('Design Team'), findsWidgets);
      expect(find.text('5 members'), findsOneWidget);
      expect(find.text('End-to-end encrypted'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Group'), findsOneWidget);
      expect(find.text('Members (5)'), findsOneWidget);
      expect(find.text('Owner'), findsNWidgets(2));
      expect(find.text('You'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      final header = tester.widget<AppAvatar>(find.byType(AppAvatar).first);
      expect(header.size, 72);
    });

    testWidgets('no lock pill when the chat is not encrypted', (tester) async {
      await tester.pumpWidget(_host(_group(3)));
      expect(find.text('End-to-end encrypted'), findsNothing);
    });

    testWidgets('a long member list gets a search above 15 only', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_group(15)));
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(_host(_group(40)));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Members (40)'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'name user3');
      await tester.pump();
      expect(find.text('Name user3'), findsOneWidget);
      expect(find.text('Name user37'), findsOneWidget);
      expect(find.text('Name user4'), findsNothing);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('No one matches that.'), findsOneWidget);
    });

    testWidgets('a member opens their chat, you open nothing', (tester) async {
      final taps = <String, int>{};
      await tester.pumpWidget(_host(_group(3), taps: taps));
      await tester.tap(find.text('Name user2'));
      await tester.tap(find.text('Name user1'));
      expect(taps, {'user2': 1});
    });

    testWidgets('narrow and large text do not overflow', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _host(_group(20, isEncrypted: true), width: 240),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('thread: rename row for owners and the members', (
      tester,
    ) async {
      final c = _conv(
        'group:care-ana.lopez',
        'group',
        'Ana Lopez',
        members: 3,
        canRename: true,
      );
      final taps = <String, int>{};
      await tester.pumpWidget(
        _host(
          ChatInfoData(
            kind: ChatInfoKind.thread,
            conversation: c,
            subtitle: '3 members',
            rows: [TicketDetailRow.of('Type', 'Thread')],
            members: _members(c),
            canRename: true,
          ),
          taps: taps,
        ),
      );
      expect(find.text('Thread'), findsOneWidget);
      expect(find.text('Members (3)'), findsOneWidget);
      await tester.tap(find.text('Rename conversation'));
      expect(taps['rename'], 1);
    });

    testWidgets('no rename row when the person may not rename', (tester) async {
      await tester.pumpWidget(_host(_group(3)));
      expect(find.text('Rename conversation'), findsNothing);
    });

    testWidgets('ticket: summary rows, members, then Open ticket', (
      tester,
    ) async {
      final c = _conv(
        'group:rec-help_ticket-217',
        'group',
        'Printer is jammed',
        members: 4,
      );
      final t = _ticket;
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final taps = <String, int>{};
      await tester.pumpWidget(
        _host(
          ChatInfoData(
            kind: ChatInfoKind.ticket,
            conversation: c,
            subtitle: 'Ticket #217',
            members: _members(c),
            ticket: t,
            ticketRows: ticketSummaryRows(t, assignedTo: 'Chen Wei'),
          ),
          taps: taps,
        ),
      );
      expect(find.text('Ticket #217'), findsWidgets);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Hardware'), findsOneWidget);
      expect(find.text('Chen Wei'), findsOneWidget);
      expect(find.text('Not in the summary'), findsNothing);
      expect(find.text('Members (4)'), findsOneWidget);
      await tester.tap(find.text('Open ticket'));
      expect(taps['ticket'], 1);
    });

    testWidgets('a thread waiting for its ticket shows a spinner or a note', (
      tester,
    ) async {
      final c = _conv('group:rec-help_ticket-9', 'group', 'Ticket #9');
      ChatInfoData data({bool isLoading = false, bool hasGap = false}) =>
          ChatInfoData(
            kind: ChatInfoKind.thread,
            conversation: c,
            subtitle: 'Group',
            isTicketLoading: isLoading,
            hasTicketGap: hasGap,
          );
      await tester.pumpWidget(_host(data(isLoading: true)));
      expect(
        find.text("The ticket isn't saved on this phone yet."),
        findsNothing,
      );
      await tester.pumpWidget(_host(data(hasGap: true)));
      expect(
        find.text("The ticket isn't saved on this phone yet."),
        findsOneWidget,
      );
    });

    testWidgets('personal: name, handle, encryption and nothing to change', (
      tester,
    ) async {
      final c = _conv('dm:ana', 'dm', 'Ana Lopez');
      await tester.pumpWidget(
        _host(
          ChatInfoData(
            kind: ChatInfoKind.personal,
            conversation: c,
            subtitle: '@ana',
            isEncrypted: true,
            rows: [TicketDetailRow.of('Username', 'ana')],
          ),
        ),
      );
      expect(find.text('Ana Lopez'), findsOneWidget);
      expect(find.text('@ana'), findsOneWidget);
      expect(find.text('End-to-end encrypted'), findsOneWidget);
      expect(find.textContaining('Members'), findsNothing);
      expect(find.text('Rename conversation'), findsNothing);
    });

    testWidgets('a group without a saved member list says so', (tester) async {
      final c = _conv('group:ops', 'group', 'Ops');
      await tester.pumpWidget(
        _host(
          ChatInfoData(
            kind: ChatInfoKind.group,
            conversation: c,
            subtitle: 'Group',
            hasMembersGap: true,
          ),
        ),
      );
      expect(
        find.text("The member list isn't saved on this phone yet."),
        findsOneWidget,
      );
    });

    testWidgets('the owner sees Add people, others do not', (tester) async {
      final taps = <String, int>{};
      final owner = ChatInfoData(
        kind: ChatInfoKind.group,
        conversation: _group(3).conversation,
        subtitle: '3 members',
        members: _group(3).members,
        canAddPeople: true,
      );
      await tester.pumpWidget(_host(owner, taps: taps));
      await tester.tap(find.text('Add people'));
      expect(taps['add'], 1);
      await tester.pumpWidget(_host(_group(3)));
      expect(find.text('Add people'), findsNothing);
    });
  });
}
