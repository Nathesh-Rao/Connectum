import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../data/models/message.dart';
import '../conversation_controller.dart';
import 'reaction_picker.dart';

/// The long-press menu of a message: Copy, Reply (direct messages and
/// groups) and Delete (my own, not in teams). Nothing else.
class MessageActionsSheet extends StatelessWidget {
  const MessageActionsSheet({
    super.key,
    required this.controller,
    required this.message,
  });

  final ConversationController controller;
  final Message message;

  static Future<void> show(
    BuildContext context,
    ConversationController controller,
    Message message,
  ) => AppBottomSheet.show<void>(
    context,
    title: 'Message',
    child: MessageActionsSheet(controller: controller, message: message),
  );

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final m = message;
    final isSettled = !m.isLocalTemp && m.status != MessageStatus.failed;
    final isForm = m.kind == 'form';
    final isFailedForm = isForm && m.status == MessageStatus.failed;
    final canCopy = !m.isDeleted && !m.isEncryptedUnsupported && !isForm;
    final canReply =
        c.canReply && isSettled && !m.isDeleted && !m.isEncryptedUnsupported;
    // A form that reached the server stays: it is a record. Only one that
    // never got there can be removed.
    final canDelete =
        m.isMine &&
        c.canDelete &&
        !m.isDeleted &&
        (!isForm || !isSettled || isFailedForm);
    final isOffline = isSettled && !c.isOnline && !isFailedForm;
    final problem = RxnString();
    final canReact = c.canReact(m);
    final isReactOffline = canReact && !c.isOnline;

    Future<void> pick(String emoji) async {
      final result = await c.react(m, emoji);
      if (result == null) {
        if (context.mounted) Navigator.of(context).pop();
      } else {
        problem.value = result;
      }
    }

    Future<void> confirmDelete() async {
      Navigator.of(context).pop();
      await AppBottomSheet.show<void>(
        context,
        title: 'Delete message?',
        child: _ConfirmDelete(controller: c, message: m),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canReact) ...[
          ReactionPicker(
            mine: {
              for (final r in c.reactionsOf(m))
                if (r.isMine) r.emoji,
            },
            isEnabled: !isReactOffline,
            onPick: pick,
          ),
          if (isReactOffline)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: Text('Needs a connection', style: AppText.readable),
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Obx(
          () => problem.value == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(problem.value!, style: AppText.readable),
                ),
        ),
        if (isFailedForm) ...[
          if (c.isInvalidFailure(m))
            AppListRow(
              title: 'Edit and resend',
              minHeight: AppSpacing.settingRowHeight,
              leading: const Icon(
                Icons.edit_outlined,
                size: 20,
                color: AppColors.muted,
              ),
              onTap: () {
                Navigator.of(context).pop();
                c.editAndResend(m);
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
                c.retryForm(m);
              },
            ),
        ],
        if (canCopy)
          AppListRow(
            title: 'Copy',
            minHeight: AppSpacing.settingRowHeight,
            leading: const Icon(Icons.copy, size: 20, color: AppColors.muted),
            onTap: () {
              c.copy(m);
              Navigator.of(context).pop();
            },
          ),
        if (canReply)
          AppListRow(
            title: 'Reply',
            minHeight: AppSpacing.settingRowHeight,
            leading: const Icon(Icons.reply, size: 20, color: AppColors.muted),
            onTap: () {
              Navigator.of(context).pop();
              c.startReply(m);
            },
          ),
        if (canDelete) ...[
          if (isOffline)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Deleting needs a connection.',
                style: AppText.readable,
              ),
            ),
          AppListRow(
            title: 'Delete',
            minHeight: AppSpacing.settingRowHeight,
            titleStyle: AppText.rowTitle.copyWith(
              color: isOffline ? AppColors.cardMuted : AppColors.error,
            ),
            leading: Icon(
              Icons.delete_outline,
              size: 20,
              color: isOffline ? AppColors.cardMuted : AppColors.error,
            ),
            onTap: isOffline ? null : confirmDelete,
          ),
        ],
      ],
    );
  }
}

class _ConfirmDelete extends StatelessWidget {
  const _ConfirmDelete({required this.controller, required this.message});

  final ConversationController controller;
  final Message message;

  @override
  Widget build(BuildContext context) {
    final problem = RxnString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'This message is removed for everyone in the conversation.',
          style: AppText.readable,
        ),
        Obx(
          () => problem.value == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(problem.value!, style: AppText.error),
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton.primary(
          label: 'Delete',
          onPressed: () async {
            final result = await controller.delete(message);
            if (result == null) {
              if (context.mounted) Navigator.of(context).pop();
            } else {
              problem.value = result;
            }
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
