import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_form_card.dart';
import '../../core/widgets/app_list_row.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/form_card.dart';
import '../conversation/widgets/chat_rows.dart';
import '../conversation/widgets/conversation_header.dart';
import '../submission_detail/submission_detail_view.dart'
    show confirmDeleteSubmission;
import '../tickets/models/card_menu.dart';
import '../tickets/widgets/record_card_actions.dart';
import '../tickets/widgets/record_menu_rows.dart';
import '../tickets/widgets/ticket_action_sheet.dart';
import 'widgets/workspace_composer.dart';
import 'widgets/workspace_welcome.dart';
import 'workspace_controller.dart';

class WorkspaceView extends GetView<WorkspaceController> {
  const WorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          ConversationHeader(
            title: 'My Work Space',
            status: null,
            avatar: const AppAvatar(name: 'My Work Space', isSquare: true),
            onBack: Get.back,
            trailing: [
              AppButton.icon(
                icon: Icons.task_alt,
                semanticLabel: 'Tasks',
                onPressed: c.openTasks,
              ),
              AppButton.icon(
                icon: Icons.fact_check_outlined,
                semanticLabel: 'Approvals',
                onPressed: c.openApprovals,
              ),
            ],
          ),
          const AppOfflineBar(),
          Expanded(
            child: Obx(
              () => AppStateView(
                state: c.viewState.value,
                errorMessage: "Couldn't load your workspace.",
                onRetry: c.retry,
                child: _Feed(controller: c),
              ),
            ),
          ),
          Obx(() {
            final text = c.notice.value;
            return AnimatedSize(
              duration: AppDurations.fast,
              curve: AppCurves.out,
              alignment: Alignment.topLeft,
              child: text == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: Text(text, style: AppText.caption),
                    ),
            );
          }),
          WorkspaceComposer(controller: c),
        ],
      ),
    );
  }
}

/// Newest at the bottom; the welcome message is the oldest, at the top.
class _Feed extends StatelessWidget {
  const _Feed({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final rows = c.rows.toList();
      return ListView.builder(
        reverse: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        itemCount: rows.length + 1,
        itemBuilder: (context, i) {
          if (i == rows.length) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WorkspaceWelcome(text: c.welcome),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.lg),
                    child: Center(
                      child: Text(
                        'Forms you submit and records sent to you show up here.',
                        style: AppText.readable,
                      ),
                    ),
                  ),
              ],
            );
          }
          final row = rows[i];
          final card = row.card;
          final note = row.note;
          if (note != null) {
            return Obx(
              () => SystemRow(
                key: ValueKey(row.key),
                text: note.text.value,
                isProblem: note.isProblem.value,
                onTap: note.convId == null ? null : () => c.openChat(note),
              ),
            );
          }
          if (card == null) {
            return DayDivider(key: ValueKey(row.key), label: row.label);
          }
          return _Card(
            key: ValueKey(row.key),
            controller: c,
            card: card,
            isReceived: row.isReceived,
          );
        },
      );
    });
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.controller,
    required this.card,
    required this.isReceived,
  });

  final WorkspaceController controller;
  final FormCardData card;
  final bool isReceived;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final state = c.stateOf(card);
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.bubbleGap),
        child: AppFormCard(
          data: card,
          isSent: !isReceived,
          senderName: isReceived ? card.by : null,
          state: state,
          problem: state == AppFormCardState.failed ? c.problemOf(card) : null,
          stripLabel: c.stripLabelOf(card),
          note: c.noteOf(card),
          actions: c.recordIdOf(card) != null
              ? RecordCardActions(
                  recordId: c.recordIdOf(card)!,
                  tickets: c.tickets,
                  onAction: (context, id) {
                    final detail = c.detailOf(card);
                    if (detail != null) {
                      TicketActionSheet.show(context, detail, id);
                    }
                  },
                )
              : null,
          isHighlighted: c.highlighted.contains(card.id),
          onTap: () => c.tap(card, isReceived: isReceived),
          onEdit: !isReceived && c.canEdit(card) ? () => c.edit(card) : null,
          onLongPress: state == AppFormCardState.failed || c.isDraft(card)
              ? () => _FailedSheet.show(context, c, card)
              : c.recordIdOf(card) != null
              ? () => _RecordSheet.show(context, c, card)
              : null,
        ),
      );
    });
  }
}

/// The menu of a card: the same list as in a chat (see `CardMenu`), read
/// when it opens, never while cards are drawn.
class _RecordSheet {
  _RecordSheet._();

  static Future<void> show(
    BuildContext context,
    WorkspaceController c,
    FormCardData card,
  ) {
    c.openRecordMenu(card);
    return AppBottomSheet.show<void>(
      context,
      title: 'Record',
      child: Builder(
        builder: (sheet) => RecordMenuRows(
          tickets: c.tickets,
          recordId: c.recordIdOf(card),
          itemsFor: (state) => c.cardMenuOf(card, state),
          onPick: (item) {
            final root = Navigator.of(sheet, rootNavigator: true).context;
            Navigator.of(sheet).pop();
            switch (item.id) {
              case CardMenuItem.edit:
                c.edit(card);
              case CardMenuItem.history:
                c.openHistory(card);
              case CardMenuItem.delete:
                c.deleteCard(card, () => confirmDeleteSubmission(root, card));
              default:
                if (item.isRecordAction) {
                  final detail = c.detailOf(card);
                  if (detail != null) {
                    TicketActionSheet.show(root, detail, item.recordActionId);
                  }
                }
            }
          },
        ),
      ),
    );
  }
}

class _FailedSheet extends StatelessWidget {
  const _FailedSheet({required this.controller, required this.card});

  final WorkspaceController controller;
  final FormCardData card;

  static Future<void> show(
    BuildContext context,
    WorkspaceController controller,
    FormCardData card,
  ) => AppBottomSheet.show<void>(
    context,
    title: 'Form',
    child: _FailedSheet(controller: controller, card: card),
  );

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      children: [
        if (c.isInvalidFailure(card) || c.isDraft(card))
          AppListRow(
            title: c.isDraft(card) ? 'Finish and send' : 'Edit and resend',
            minHeight: AppSpacing.settingRowHeight,
            leading: const Icon(
              Icons.edit_outlined,
              size: 20,
              color: AppColors.muted,
            ),
            onTap: () {
              Navigator.of(context).pop();
              c.editAndResend(card);
            },
          )
        else
          AppListRow(
            title: 'Retry',
            minHeight: AppSpacing.settingRowHeight,
            leading: const Icon(
              Icons.refresh,
              size: 20,
              color: AppColors.muted,
            ),
            onTap: () {
              Navigator.of(context).pop();
              c.tap(card);
            },
          ),
        AppListRow(
          title: 'Delete',
          minHeight: AppSpacing.settingRowHeight,
          titleStyle: AppText.rowTitle.copyWith(color: AppColors.error),
          leading: const Icon(
            Icons.delete_outline,
            size: 20,
            color: AppColors.error,
          ),
          onTap: () {
            Navigator.of(context).pop();
            c.discard(card);
          },
        ),
      ],
    );
  }
}
