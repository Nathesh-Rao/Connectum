import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_detail_row.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_progress_bar.dart';
import '../../core/widgets/app_refresh.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/ticket.dart';
import 'models/ticket_text.dart';
import 'ticket_detail_controller.dart';
import 'tickets_texts.dart';
import 'widgets/ticket_action_sheet.dart';
import 'widgets/ticket_history_timeline.dart';
import 'widgets/ticket_status_chip.dart';

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
    final table = t.table!;
    final actions = c.actions;
    final isBusy = c.isBusy.value;
    final withName = c.tickets.isMe(t.withWhom)
        ? TicketsTexts.you
        : c.tickets.nameOf(t.withWhom);
    final rows = <MapEntry<String, String>>[
      for (final e in t.values.entries)
        if (!table.headerFields.contains(e.key) &&
            TicketText.value(e.value).isNotEmpty)
          MapEntry(t.form?.labelOf(e.key) ?? e.key, TicketText.value(e.value)),
    ];
    return AppRefresh(
      onRefresh: () => c.reload(isQuiet: false),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(t.title, style: AppText.subtitle),
              const SizedBox(height: AppSpacing.xxs),
              Text(t.ref, style: AppText.rowCaption),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TicketStatusChip(ticket: t),
              ),
              if (!t.isAwaitingApproval) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('${TicketsTexts.withWhom} $withName', style: AppText.body),
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
              if (actions.isNotEmpty || c.canEdit) ...[
                for (var i = 0; i < actions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: i == 0
                        ? AppButton.primary(
                            label: actions[i].name,
                            isCentered: true,
                            onPressed: isBusy
                                ? null
                                : () => TicketActionSheet.show(
                                    context,
                                    c,
                                    actions[i],
                                  ),
                          )
                        : AppButton.secondary(
                            label: actions[i].name,
                            onPressed: isBusy
                                ? null
                                : () => TicketActionSheet.show(
                                    context,
                                    c,
                                    actions[i],
                                  ),
                          ),
                  ),
                if (c.canEdit)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: AppButton.secondary(
                      label: TicketsTexts.edit,
                      onPressed: isBusy ? null : c.edit,
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
              ],
              for (final r in rows)
                AppDetailRow(caption: r.key, value: r.value),
              AppDetailRow(
                caption: TicketsTexts.raisedBy,
                value: c.tickets.isMe(t.by)
                    ? TicketsTexts.you
                    : c.tickets.nameOf(t.by),
              ),
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
