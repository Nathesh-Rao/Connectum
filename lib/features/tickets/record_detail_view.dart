import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_refresh.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../inbox/widgets/inbox_card_frame.dart';
import '../smart_view/widgets/sv_file_preview_dialog.dart';
import 'models/record_kind.dart';
import 'ticket_detail_controller.dart';
import 'tickets_texts.dart';
import 'widgets/record_action_bar.dart';
import 'widgets/record_detail_header.dart';
import 'widgets/record_fields_card.dart';
import 'widgets/ticket_history_panel.dart';

/// One record in full, whatever it is (ticket, submission or an approval):
/// a top bar with the kind and `#id`, who raised it and when, the status as
/// a strip, the answers as a grouped card, the history as a timeline, and a
/// sticky bar with only the actions that apply. The corners carry the same
/// soft washes as the Inbox card: the status colour top right, the person's
/// colour top left.
class RecordDetailView extends GetView<TicketDetailController> {
  const RecordDetailView({super.key});

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
      bottomBar: RecordActionBar(controller: c),
      body: Stack(
        children: [
          Positioned.fill(
            child: Obx(() => InboxCardWash(tone: c.cardStatus.tone)),
          ),
          Positioned.fill(
            child: Obx(() => InboxAvatarWash(picture: c.pictureOf(c.raiser))),
          ),
          Column(
            children: [
              _TopBar(controller: c),
              const AppOfflineBar(),
              Expanded(child: Obx(() => _body(context))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = controller;
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
    if (state == AppViewState.loading && ticket == null) {
      return const RecordDetailSkeleton();
    }
    if (state != AppViewState.content || ticket == null) {
      return AppStateView(
        state: state,
        errorMessage: TicketsTexts.detailError,
        onRetry: () => c.reload(isQuiet: false),
        child: const SizedBox.shrink(),
      );
    }
    return _Content(controller: c);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final TicketDetailController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.xxs,
      ),
      child: Row(
        children: [
          AppButton.icon(
            icon: Icons.arrow_back,
            semanticLabel: 'Back',
            onPressed: Get.back,
          ),
          Expanded(
            child: Obx(() {
              final kind = c.ticket.value == null
                  ? RecordKind.submission.title
                  : c.kind.title;
              return Text(
                '$kind #${c.ticketId}',
                key: const ValueKey('record-title'),
                style: AppText.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.controller});

  final TicketDetailController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final t = c.ticket.value;
      if (t == null) return const SizedBox.shrink();
      final state = c.state.value;
      final first = state?.statuses.isEmpty ?? true
          ? null
          : state!.statuses.first;
      final raiser = c.raiser;
      final strip = c.statusText;
      final holders = c.holders.where((h) => h.isNotEmpty).toList();
      final completion = state?.completion ?? t.completion;
      final hasWith = !t.isAwaitingApproval && holders.isNotEmpty;
      return AppRefresh(
        onRefresh: () => c.reload(isQuiet: false),
        slivers: [
          SliverToBoxAdapter(
            child: RecordIdentity(
              name: c.nameOfUser(raiser),
              picture: c.pictureOf(raiser),
              subject: t.title,
              ts: c.card.value?.ts ?? t.ts,
            ),
          ),
          if (strip.isNotEmpty)
            SliverToBoxAdapter(
              child: InboxStatusStrip(status: c.cardStatus, text: strip),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: RecordFieldsCard(
                leading: [
                  if (hasWith)
                    RecordFieldLine(
                      icon: Icons.person_outline_rounded,
                      tone: InboxCardStatus.assigned.tone,
                      label: TicketsTexts.withWhom,
                      child: RecordPeople(
                        users: holders,
                        nameOf: c.nameOfUser,
                        pictureOf: c.pictureOf,
                      ),
                    ),
                  if (hasWith && completion > 0)
                    RecordFieldLine(
                      icon: Icons.donut_large_rounded,
                      tone: InboxCardStatus.completed.tone,
                      label: TicketsTexts.completion,
                      child: RecordCompletion(percent: completion),
                    ),
                ],
                rows: c.rows,
                nameOf: c.nameOfUser,
                pictureOf: c.pictureOf,
                onOpenFiles: c.hasFiles
                    ? (files, index) => SvFilePreviewDialog.show(
                        context,
                        c.newFilePreview(files, index),
                      )
                    : null,
                isFilesOpen: (name) => c.openFiles.contains(name),
                onToggleFiles: c.toggleFiles,
              ),
            ),
          ),
          if (c.isUnopenable.value)
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
            )
          else
            SliverToBoxAdapter(
              child: Obx(
                () => TicketHistoryPanel(
                  history: c.history.value,
                  state: c.historyState.value,
                  ticket: t,
                  first: first,
                  nameOf: c.nameOfUser,
                  pictureOf: c.pictureOf,
                  onRefresh: () => c.reload(isQuiet: false),
                ),
              ),
            ),
        ],
      );
    });
  }
}
