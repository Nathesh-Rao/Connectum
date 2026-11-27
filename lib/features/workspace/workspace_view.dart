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
import '../../core/widgets/message_selection/selectable_row.dart';
import '../../core/widgets/message_selection/selection_app_bar.dart';
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
import 'widgets/workspace_locked_hint.dart';
import 'widgets/workspace_message.dart';
import 'widgets/workspace_sample_row.dart';
import 'widgets/workspace_selection.dart';
import 'widgets/workspace_pinned_bar.dart';
import 'widgets/workspace_saved_sheet.dart';
import 'widgets/workspace_welcome.dart';
import 'workspace_controller.dart';
import 'workspace_tour.dart';

class WorkspaceView extends GetView<WorkspaceController> {
  const WorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Obx(
        () => PopScope(
          canPop: !c.selection.isActive && !c.isTourActive,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (c.isTourActive) {
              c.cancelTour();
            } else {
              c.selection.clear();
            }
          },
          child: Column(
            children: [
              SelectionHeaderSwitcher(
                isSelecting:
                    c.selection.isActive ||
                    (c.tour?.demo.selection.isActive ?? false),
                selectionBar: KeyedSubtree(
                  key: c.tour?.selectionBarKey,
                  child: _selectionBar(c),
                ),
                header: KeyedSubtree(
                  key: c.tour?.headerKey,
                  child: ConversationHeader(
                    title: 'My Work Space',
                    status: null,
                    avatar: const AppAvatar(
                      name: 'My Work Space',
                      isSquare: true,
                    ),
                    onBack: Get.back,
                    trailing: [
                      AppButton.icon(
                        icon: Icons.bookmark_border,
                        semanticLabel: 'Saved notes',
                        onPressed: () => WorkspaceSavedSheet.show(context, c),
                      ),
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
                ),
              ),
              const AppOfflineBar(),
              WorkspacePinnedBar(controller: c),
              Expanded(
                child: KeyedSubtree(
                  key: c.tour?.areaKey,
                  child: Obx(
                    () => AppStateView(
                      state: c.viewState.value,
                      errorMessage: "Couldn't load your workspace.",
                      onRetry: c.retry,
                      child: _Feed(controller: c),
                    ),
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
                          child: Text(text, style: AppText.wsMeta),
                        ),
                );
              }),
              KeyedSubtree(
                key: c.tour?.composerKey,
                child: WorkspaceComposer(controller: c),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selection bar: the notes' own, or the sample's while the tour shows
/// the sample note.
Widget _selectionBar(WorkspaceController c) => Obx(() {
  final demo = c.tour?.demo;
  final isSample = demo != null && demo.isOn.value;
  final bar = WorkspaceSelectionBar(
    controller: c,
    sample: isSample ? demo : null,
  );
  return isSample ? IgnorePointer(child: bar) : bar;
});

/// Newest at the bottom; the welcome message is the oldest, at the top.
class _Feed extends StatelessWidget {
  const _Feed({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final rows = c.rows.toList();
      final tour = c.tour;
      final hasSample = tour != null && tour.demo.isOn.value;
      final sampleCount = hasSample ? 1 : 0;
      // The tour presses and holds the newest note and slides the newest one
      // that can be replied to.
      final notes = [
        for (final r in rows)
          if (r.message != null) r.message!,
      ];
      final holdId = tour == null ? null : WorkspaceTour.holdNote(notes)?.msgId;
      final swipeId = tour == null
          ? null
          : WorkspaceTour.swipeNote(notes, c.targetOf)?.msgId;
      return ListView.builder(
        controller: c.scroll,
        reverse: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        itemCount: rows.length + sampleCount + 1,
        itemBuilder: (context, index) {
          if (hasSample && index == 0) return WorkspaceSampleRow(tour: tour);
          final i = index - sampleCount;
          if (i == rows.length) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WorkspaceWelcome(text: c.welcome),
                if (c.hasLockedNotes)
                  WorkspaceLockedHint(onTap: c.openEncryptionSetup),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.lg),
                    child: Center(
                      child: Text(
                        'Forms you submit and records sent to you show up here.',
                        style: AppText.wsSubtitle,
                      ),
                    ),
                  ),
              ],
            );
          }
          final row = rows[i];
          final card = row.card;
          final note = row.note;
          final message = row.message;
          if (message != null) {
            final bubble = SelectableRow(
              selection: c.selection,
              id: message.msgId,
              swipeKey: message.msgId == swipeId ? tour?.swipeKey : null,
              onSwipeReply: c.targetOf(message).canReply
                  ? () => c.startReply(message)
                  : null,
              child: Obx(
                () => WorkspaceMessage(
                  key: c.keyForNote(message.msgId),
                  message: message,
                  original: c.originalOf(message),
                  me: c.me,
                  isHighlighted: c.flashId.value == message.msgId,
                  isSaved: c.isSaved(message),
                  isPinned: c.isPinned(message),
                  onRetry: () => c.retryNote(message),
                  onSetUpEncryption: c.openEncryptionSetup,
                  onLongPress: () => c.selection.onLongPress(message.msgId),
                ),
              ),
            );
            return message.msgId == holdId
                ? KeyedSubtree(key: tour?.noteKey, child: bubble)
                : bubble;
          }
          if (note != null) {
            return Obx(
              () => SystemRow(
                key: ValueKey(row.key),
                text: note.text.value,
                isProblem: note.isProblem.value,
                onTap: note.convId == null ? null : () => c.openChat(note),
                style: AppText.wsMeta,
              ),
            );
          }
          if (card == null) {
            return DayDivider(
              key: ValueKey(row.key),
              label: row.label,
              style: AppText.wsSection,
            );
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
          text: AppFormCardText.workspace,
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
                  summary: card.record,
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
