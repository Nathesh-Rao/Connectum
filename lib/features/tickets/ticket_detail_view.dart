import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_tones.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_action_bar.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_progress_bar.dart';
import '../../core/widgets/app_refresh.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/ticket.dart';
import 'models/ticket_action_style.dart';
import 'models/ticket_detail_row.dart';
import 'models/ticket_rows.dart';
import 'ticket_detail_controller.dart';
import 'tickets_texts.dart';
import 'widgets/ticket_action_sheet.dart';
import 'widgets/ticket_history_timeline.dart';
import 'widgets/ticket_detail_list.dart';
import 'widgets/ticket_status_pill.dart';

class TicketDetailView extends GetView<TicketDetailController> {
  const TicketDetailView({super.key});

  @override
  String? get tag => Get.parameters['id'];

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyGeneric,
      AppStateImageKind.error,
      AppStateImageKind.offline,
    ]);
    return AppScaffold(
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
                const Expanded(
                  child: Text(TicketsTexts.detailTitle, style: AppText.title),
                ),
              ],
            ),
          ),
          const AppOfflineBar(),
          Expanded(
            child: Obx(() {
              final state = c.viewState.value;
              final ticket = c.ticket.value;
              if (c.isGone.value) {
                return const AppStateView(
                  state: AppViewState.empty,
                  emptyTitle: TicketsTexts.detailGoneTitle,
                  emptyMessage: TicketsTexts.detailGoneMessage,
                  child: SizedBox.shrink(),
                );
              }
              if (c.isNotTicket.value) {
                return const AppStateView(
                  state: AppViewState.empty,
                  emptyTitle: TicketsTexts.detailNotTicketTitle,
                  emptyMessage: TicketsTexts.detailNotTicketMessage,
                  child: SizedBox.shrink(),
                );
              }
              if (state != AppViewState.content || ticket == null) {
                return AppStateView(
                  state: state,
                  errorMessage: TicketsTexts.detailError,
                  onRetry: () => c.reload(isQuiet: false),
                  child: const SizedBox.shrink(),
                );
              }
              return _Content(controller: c, ticket: ticket);
            }),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.controller, required this.ticket});

  final TicketDetailController controller;
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = ticket;
    final actions = c.actions;
    final isBusy = c.isBusy.value;
    final withName = c.tickets.isMe(t.withWhom)
        ? TicketsTexts.you
        : c.tickets.nameOf(t.withWhom);
    final rows = [
      ...ticketValueRows(t),
      TicketDetailRow.of(
        TicketsTexts.raisedBy,
        c.tickets.isMe(t.by) ? TicketsTexts.you : c.tickets.nameOf(t.by),
      ),
    ];
    return AppRefresh(
      onRefresh: () => c.reload(isQuiet: false),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(t.title, style: AppText.subtitle),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  TicketPill(
                    label: '${TicketsTexts.ticketMarker} #${t.id}',
                    icon: Icons.confirmation_number_outlined,
                    tone: AppTones.slate,
                  ),
                  TicketStatusPill(ticket: t),
                ],
              ),
              if (!t.isAwaitingApproval) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        '${TicketsTexts.withWhom} $withName',
                        style: AppText.body,
                      ),
                    ),
                  ],
                ),
                if (t.completion > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: AppProgressBar(value: t.completion / 100),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        TicketsTexts.percentValue(t.completion),
                        style: AppText.readableStrong,
                      ),
                    ],
                  ),
                ],
              ] else ...[
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  TicketsTexts.waitingForApprovalNote,
                  style: AppText.readable,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (actions.isNotEmpty) ...[
                AppActionBar(
                  items: actionItemsOf(actions),
                  layout: AppActionLayout.full,
                  isEnabled: !isBusy,
                  onTap: (item) => TicketActionSheet.show(
                    context,
                    c,
                    actions.firstWhere((a) => a.name == item.id),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              if (c.canEdit) ...[
                AppButton.secondary(
                  label: TicketsTexts.edit,
                  icon: Icons.edit_outlined,
                  onPressed: isBusy ? null : c.edit,
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              const SizedBox(height: AppSpacing.xs),
              TicketDetailList(rows: rows),
              const SizedBox(height: AppSpacing.md),
              const Text(TicketsTexts.historyTitle, style: AppText.subtitle),
              const SizedBox(height: AppSpacing.sm),
              _History(controller: c),
              const SizedBox(height: AppSpacing.xl),
            ]),
          ),
        ),
      ],
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.controller});

  final TicketDetailController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final entries = c.history.toList();
      if (entries.isEmpty) {
        final failed = c.historyState.value == AppViewState.error;
        return Text(
          failed ? TicketsTexts.historyError : TicketsTexts.historyEmpty,
          style: AppText.readable.copyWith(color: AppColors.muted),
        );
      }
      return TicketHistoryTimeline(entries: entries, nameOf: c.tickets.nameOf);
    });
  }
}
