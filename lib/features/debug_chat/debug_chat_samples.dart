import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_action_bar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_form_card.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../data/models/conversation.dart';
import '../../data/models/form_card.dart';
import '../../data/models/form_entry.dart';
import '../../data/models/ticket.dart';
import '../chat_info/models/chat_info.dart';
import '../chat_info/widgets/chat_info_body.dart';
import '../tickets/models/ticket_action_style.dart';
import '../tickets/models/ticket_rows.dart';

/// Debug only (see "Before release" in CLAUDE.md): the Chat info page for
/// every kind of conversation, and ticket cards with 0 to 6 actions, from
/// sample data. Nothing is read or sent.
class DebugChatSamples extends StatelessWidget {
  const DebugChatSamples({super.key});

  static const _names = [
    'Ana Lopez',
    'Bruno Silva',
    'Chen Wei',
    'Dara Okafor',
    'Eli Katz',
    'Farah Haddad',
    'Gus Moreno',
    'Hana Sato',
  ];

  static List<String> _users(int n) => [
    for (var i = 0; i < n; i++)
      '${_names[i % _names.length].split(' ').first.toLowerCase()}${i < _names.length ? '' : i}',
  ];

  static Conversation _conv(
    String id,
    String kind,
    String title, {
    int members = 0,
    String owner = '',
    bool canRename = false,
  }) {
    final users = _users(members);
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

  static String _nameOf(String user) {
    final first = _names.where((n) => n.toLowerCase().startsWith(user));
    return first.isEmpty ? user : first.first;
  }

  static List<ChatInfoMember> _members(Conversation c) =>
      ChatInfoMember.listOf(c, me: 'ana', nameOf: _nameOf);

  static Ticket get _ticket {
    const fields = {
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
    };
    return Ticket(
      id: 217,
      by: 'bruno',
      ts: DateTime.now().millisecondsSinceEpoch,
      tstruct: 'help_ticket',
      values: const {
        'ticket no': 'T-217',
        'title': 'Printer on floor 3 is jammed',
        'category': 'Hardware',
        'subtype': 'Printer',
        'priority': 'High',
        'need by': '2026-11-12',
        'expected completion': '2026-11-10',
        'assigned to': 'chen',
        'status': 'In progress',
        'completion': 40,
      },
      form: const TicketForm(
        key: 'help_ticket',
        caption: 'Help ticket',
        fields: fields,
        table: TicketTable(
          field: 'status',
          assignee: 'assigned to',
          completion: 'completion',
          subject: 'title',
          statuses: [
            TicketStatus('Open'),
            TicketStatus('In progress'),
            TicketStatus('Closed', isFinal: true),
          ],
        ),
      ),
    );
  }

  static final _variants = <(String, ChatInfoData)>[
    (
      'Personal chat',
      ChatInfoData(
        kind: ChatInfoKind.personal,
        conversation: _conv('dm:ana', 'dm', 'Ana Lopez'),
        subtitle: '@ana',
        isEncrypted: true,
        rows: const [],
      ),
    ),
    (
      'Group (5 members, I own it)',
      () {
        final c = _conv(
          'group:design team',
          'group',
          'Design Team',
          members: 5,
          owner: 'ana',
        );
        return ChatInfoData(
          kind: ChatInfoKind.group,
          conversation: c,
          subtitle: '5 members',
          members: _members(c),
          canAddPeople: true,
        );
      }(),
    ),
    (
      'Group (40 members, encrypted, search)',
      () {
        final c = _conv(
          'group:everyone-on-site',
          'group',
          'Everyone On Site',
          members: 40,
          owner: 'bruno',
        );
        return ChatInfoData(
          kind: ChatInfoKind.group,
          conversation: c,
          subtitle: '40 members',
          isEncrypted: true,
          members: _members(c),
        );
      }(),
    ),
    (
      'Group (members not saved yet)',
      ChatInfoData(
        kind: ChatInfoKind.group,
        conversation: _conv('group:ops', 'group', 'Ops'),
        subtitle: 'Group',
        hasMembersGap: true,
      ),
    ),
    (
      'Thread (care, I may rename)',
      () {
        final c = _conv(
          'group:care-ana.lopez',
          'group',
          'Ana Lopez',
          members: 3,
          owner: 'bruno',
          canRename: true,
        );
        return ChatInfoData(
          kind: ChatInfoKind.thread,
          conversation: c,
          subtitle: '3 members',
          members: _members(c),
          canRename: true,
        );
      }(),
    ),
    (
      'Ticket',
      () {
        final c = _conv(
          'group:rec-help_ticket-217',
          'group',
          'Printer on floor 3 is jammed',
          members: 4,
          owner: 'bruno',
        );
        final t = _ticket;
        return ChatInfoData(
          kind: ChatInfoKind.ticket,
          conversation: c,
          subtitle: 'Ticket #217',
          members: _members(c),
          ticket: t,
          ticketRows: ticketSummaryRows(t, assignedTo: 'Chen Wei'),
        );
      }(),
    ),
    (
      'Ticket (loading)',
      ChatInfoData(
        kind: ChatInfoKind.thread,
        conversation: _conv(
          'group:rec-help_ticket-218',
          'group',
          'Ticket #218',
          members: 2,
        ),
        subtitle: 'Ticket #218',
        isTicketLoading: true,
      ),
    ),
    (
      'Ticket (not saved yet)',
      ChatInfoData(
        kind: ChatInfoKind.thread,
        conversation: _conv(
          'group:rec-help_ticket-219',
          'group',
          'Ticket #219',
        ),
        subtitle: 'Ticket #219',
        hasTicketGap: true,
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Chat info (sample)', style: AppText.subtitle),
          for (final (label, data) in _variants) ...[
            const SizedBox(height: AppSpacing.xs),
            AppButton.secondary(
              label: label,
              onPressed: () => Get.to<void>(() => _Preview(data: data)),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Text('Ticket card actions (sample)', style: AppText.subtitle),
          for (final n in const [0, 1, 2, 3, 6]) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$n actions, received then sent (tap the bar to expand)',
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.xxs),
            _SampleCard(count: n),
            const SizedBox(height: AppSpacing.xs),
            _SampleCard(count: n, isSent: true),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.data});

  final ChatInfoData data;

  @override
  Widget build(BuildContext context) => AppScaffold(
    isScrollable: false,
    padding: EdgeInsets.zero,
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.xxs,
          ),
          child: Row(
            children: [
              AppButton.icon(
                icon: Icons.arrow_back,
                semanticLabel: 'Back',
                onPressed: Get.back,
              ),
              const Expanded(child: Text('Chat info', style: AppText.title)),
            ],
          ),
        ),
        Expanded(
          child: ChatInfoBody(data: data, onOpenMember: (_) {}),
        ),
      ],
    ),
  );
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.count, this.isSent = false});

  final int count;
  final bool isSent;

  static const _actions = [
    ('Status update', Icons.published_with_changes),
    ('Complete', Icons.check_circle_outline),
    ('Return', Icons.undo),
    ('Drop', Icons.remove_circle_outline),
    ('Reassign', Icons.swap_horiz),
    ('Escalate', Icons.trending_up),
  ];

  @override
  Widget build(BuildContext context) {
    final card = FormCardData(
      id: '217',
      caption: 'Help ticket',
      structure: 'help_ticket',
      scope: 'user',
      by: 'bruno',
      ts: DateTime.now().millisecondsSinceEpoch,
      isTicket: true,
      entries: const [
        FormEntry(name: 'title', caption: 'Title', text: 'Printer is jammed'),
        FormEntry(name: 'priority', caption: 'Priority', text: 'High'),
      ],
    );
    return AppFormCard(
      data: card,
      isSent: isSent,
      statusMark: isSent
          ? const Icon(Icons.done_all, size: 14, color: AppColors.cardMuted)
          : null,
      stripLabel: 'Ticket #217',
      onTap: () {},
      actions: count == 0
          ? null
          : AppFormCardActionArea(
              child: AppActionBar(
                inset: AppFormCardActionArea.inset,
                onTap: (_) {},
                items: [
                  for (final (label, icon) in _actions.take(count))
                    ActionItem(
                      id: label,
                      label: label,
                      icon: icon,
                      tone: actionStyleFor(label).tone,
                    ),
                ],
              ),
            ),
    );
  }
}
