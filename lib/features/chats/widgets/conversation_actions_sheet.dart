import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../data/models/conversation.dart';
import '../chats_controller.dart';
import 'record_rename_sheet.dart';

/// The long-press menu of a conversation row: pin and mute, and rename for a
/// record conversation I saved the record of.
class ConversationActionsSheet extends StatelessWidget {
  const ConversationActionsSheet({
    super.key,
    required this.conversation,
    required this.controller,
  });

  final Conversation conversation;
  final ChatsController controller;

  static Future<void> show(
    BuildContext context,
    ChatsController controller,
    Conversation conversation,
  ) => AppBottomSheet.show<void>(
    context,
    title: conversation.title,
    child: ConversationActionsSheet(
      conversation: conversation,
      controller: controller,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final message = RxnString();
    final c = conversation;
    Future<void> run(Future<String?> Function() action) async {
      final problem = await action();
      if (problem == null) {
        if (context.mounted) Navigator.of(context).pop();
      } else {
        message.value = problem;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(() {
          final note = controller.isOffline
              ? ChatsController.needsConnection
              : message.value;
          if (note == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              note,
              style: AppText.readable.copyWith(color: AppColors.muted),
            ),
          );
        }),
        AppListRow(
          title: c.isPinned ? 'Unpin' : 'Pin',
          minHeight: AppSpacing.settingRowHeight,
          leading: Icon(
            c.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            size: 20,
            color: AppColors.muted,
          ),
          onTap: () => run(() => controller.togglePin(c)),
        ),
        AppListRow(
          title: c.isMuted ? 'Unmute' : 'Mute',
          minHeight: AppSpacing.settingRowHeight,
          leading: Icon(
            c.isMuted ? Icons.volume_up_outlined : Icons.volume_off,
            size: 20,
            color: AppColors.muted,
          ),
          onTap: () => run(() => controller.toggleMute(c)),
        ),
        if (c.canRename)
          AppListRow(
            title: 'Rename',
            minHeight: AppSpacing.settingRowHeight,
            leading: const Icon(
              Icons.edit_outlined,
              size: 20,
              color: AppColors.muted,
            ),
            onTap: () {
              final navigator = Navigator.of(context)..pop();
              RecordRenameSheet.show(navigator.context, controller, c);
            },
          ),
      ],
    );
  }
}
