import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_refresh.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/conversation_avatar.dart';
import '../../tickets/tickets_texts.dart';
import '../../tickets/widgets/ticket_detail_list.dart';
import '../../tickets/widgets/ticket_status_pill.dart';
import '../models/chat_info.dart';
import 'chat_info_members.dart';

/// The info page without its screen: [data] is drawn and nothing else is
/// read, so the debug page can show every variant from sample data.
/// [onRefresh] is given only when something on the page is fetched remotely.
class ChatInfoBody extends StatelessWidget {
  const ChatInfoBody({
    super.key,
    required this.data,
    this.onOpenTicket,
    this.onRename,
    this.onAddPeople,
    this.onOpenMember,
    this.onRefresh,
  });

  static const avatarSize = 72.0;

  final ChatInfoData data;
  final VoidCallback? onOpenTicket;
  final VoidCallback? onRename;
  final VoidCallback? onAddPeople;
  final ValueChanged<ChatInfoMember>? onOpenMember;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final ticket = d.ticket;
    final children = <Widget>[
      const SizedBox(height: AppSpacing.md),
      _Header(data: d),
      const SizedBox(height: AppSpacing.md),
      if (ticket != null) ...[
        Text(ticket.title, style: AppText.subtitle),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            TicketPill(
              label: '${TicketsTexts.ticketMarker} #${ticket.id}',
              icon: Icons.confirmation_number_outlined,
              tone: AppTones.slate,
            ),
            TicketStatusPill(ticket: ticket),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        TicketDetailList(rows: d.ticketRows),
      ] else ...[
        TicketDetailList(rows: d.rows),
        if (d.isTicketLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Center(child: AppSpinner()),
          ),
        if (d.hasTicketGap)
          const _Note("The ticket isn't saved on this phone yet."),
      ],
      if (d.canRename && onRename != null)
        AppListRow(
          title: 'Rename conversation',
          minHeight: AppSpacing.settingRowHeight,
          leading: const Icon(
            Icons.edit_outlined,
            size: 20,
            color: AppColors.muted,
          ),
          onTap: onRename,
        ),
      if (d.hasMembers) ...[
        const SizedBox(height: AppSpacing.md),
        if (d.members.isNotEmpty)
          ChatInfoMembers(
            members: d.members,
            hasSearch: d.hasSearch,
            onOpen: onOpenMember ?? (_) {},
            onAddPeople: d.canAddPeople ? onAddPeople : null,
          )
        else if (d.hasMembersGap)
          const _Note("The member list isn't saved on this phone yet."),
      ],
      if (ticket != null && onOpenTicket != null) ...[
        const SizedBox(height: AppSpacing.md),
        AppButton.primary(label: 'Open ticket', onPressed: onOpenTicket),
      ],
      const SizedBox(height: AppSpacing.xl),
    ];
    final padded = SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      sliver: SliverList(delegate: SliverChildListDelegate(children)),
    );
    final refresh = onRefresh;
    if (refresh != null) {
      return AppRefresh(onRefresh: refresh, slivers: [padded]);
    }
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [padded],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data});

  final ChatInfoData data;

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Column(
      children: [
        conversationAvatarFor(d.conversation, size: ChatInfoBody.avatarSize),
        const SizedBox(height: AppSpacing.sm),
        Text(d.title, textAlign: TextAlign.center, style: AppText.title),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          d.subtitle,
          textAlign: TextAlign.center,
          style: AppText.readable.copyWith(color: AppColors.muted),
        ),
        if (d.isEncrypted) ...[
          const SizedBox(height: AppSpacing.xs),
          const TicketPill(
            label: 'End-to-end encrypted',
            icon: Icons.lock_outline,
            tone: AppTones.green,
          ),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Text(text, style: AppText.readable.copyWith(color: AppColors.muted)),
  );
}
