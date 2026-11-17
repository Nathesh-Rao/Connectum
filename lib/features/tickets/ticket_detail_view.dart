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
import 'widgets/fixed_top_layout.dart';
import 'widgets/ticket_history_panel.dart';
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
    return Obx(() {
      final t = c.ticket.value ?? ticket;
      final state = c.state.value;
      final first = state?.statuses.isEmpty ?? true
          ? null
          : state!.statuses.first;
      final top = _Top(controller: c, ticket: t);
      if (c.isUnopenable.value) {
        return AppRefresh(
          onRefresh: () => c.reload(isQuiet: false),
          slivers: [
            SliverToBoxAdapter(child: top),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.page,
                0,
                AppSpacing.page,
                AppSpacing.xl,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  TicketsTexts.unopenableNotice,
                  style: AppText.readable,
                ),
              ),
            ),
          ],
        );
      }
      Widget panel({required bool isInline}) => Obx(
        () => TicketHistoryPanel(
          history: c.history.value,
          state: c.historyState.value,
          ticket: t,
          first: first,
          nameOf: c.tickets.nameOf,
          onRefresh: () => c.reload(isQuiet: false),
          isInline: isInline,
        ),
      );
      return FixedTopLayout(
        top: top,
        fixedPanel: panel(isInline: false),
        inlinePanel: panel(isInline: true),
        onRefresh: () => c.reload(isQuiet: false),
      );
    });
  }
}

/// Everything above the History panel: it stays where it is.
class _Top extends StatelessWidget {
  const _Top({required this.controller, required this.ticket});

  final TicketDetailController controller;
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = ticket;
    final items = c.items;
    final state = c.state.value;
    final isBusy = c.isBusy.value;
    final withName = c.holders
        .map((u) => c.tickets.isMe(u) ? TicketsTexts.you : c.tickets.nameOf(u))
        .join(', ');
    final completion = state?.completion ?? t.completion;
    final rows = [
      ...ticketValueRows(t, status: state?.status ?? ''),
      TicketDetailRow.of(
        TicketsTexts.raisedBy,
        c.tickets.isMe(t.by) ? TicketsTexts.you : c.tickets.nameOf(t.by),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
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
              TicketStatusPill(
                ticket: t,
                status: state?.status,
                isFinal: state?.isFinal,
                first: state?.statuses.isEmpty ?? true
                    ? null
                    : state!.statuses.first,
              ),
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
            if (completion > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(child: AppProgressBar(value: completion / 100)),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    TicketsTexts.percentValue(completion),
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
          if (items.isNotEmpty) ...[
            AppActionBar(
              items: actionItemsOf(items),
              layout: AppActionLayout.full,
              isEnabled: !isBusy,
              onTap: (item) => TicketActionSheet.show(context, c, item.id),
            ),
            for (final i in items)
              if (!i.isEnabled && i.why.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Text(
                    '${i.label}: ${i.why}',
                    style: AppText.readable.copyWith(color: AppColors.muted),
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
        ],
      ),
    );
  }
}
