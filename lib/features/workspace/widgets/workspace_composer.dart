import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/conversation/conversation.dart';
import 'package:connectum/features/forms/forms.dart';
import '../workspace_controller.dart';
import 'workspace_context_bar.dart';

/// The workspace composer: `#` opens the commands list, `@name text` messages
/// that person, and any other text is a note of mine (kept on the server, sent
/// again by the outbox until it is acknowledged). The forms button works as
/// everywhere else. There is no attach button: a file note is not built.
class WorkspaceComposer extends StatelessWidget {
  const WorkspaceComposer({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommandsPanel(
          prompt: c.prompt,
          onPick: c.pickCommand,
          onPickItem: c.pickCommandItem,
          onPickName: c.renameCommand,
          isOnline: () => c.commands.isOnline,
          panelKey: c.commandsTour?.panelKey,
          rowKeyOf: c.commandsTour?.rowKeyOf,
        ),
        Obx(
          () => WorkspaceContextBar(
            message: c.editing.value,
            label: 'Editing note',
            cancelLabel: 'Cancel edit',
            onCancel: c.cancelEdit,
          ),
        ),
        Obx(
          () => WorkspaceContextBar(
            message: c.replying.value,
            label: 'Replying to note',
            cancelLabel: 'Cancel reply',
            onCancel: c.cancelReply,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.composerPad),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.line),
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadius.bubble),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FormsButton(
                  onTap: () => FormsPickerSheet.show(context, c.picker),
                ),
                Expanded(
                  child: AppTextField(
                    controller: c.text,
                    focusNode: c.focus,
                    hint: WorkspaceController.placeholder,
                    textStyle: AppText.chatInput,
                    minLines: 1,
                    maxLines: 5,
                    minHeight: AppSpacing.composerButton,
                    horizontalPadding: AppSpacing.xxs,
                    fillColor: Colors.transparent,
                    hasFocusRing: false,
                    borderColor: Colors.transparent,
                    borderRadius: BorderRadius.zero,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.newline,
                    onChanged: c.onChanged,
                  ),
                ),
                Obx(
                  () => ComposerSendButton(
                    key: c.commandsTour?.sendKey,
                    isActive: c.length.value > 0 && !c.runner.isRunning.value,
                    onTap: c.send,
                  ),
                ),
              ],
            ),
          ),
        ),
        Obx(() {
          final hint = c.nudge.value;
          if (hint == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(hint, style: AppText.wsMeta),
          );
        }),
      ],
    );
  }
}
