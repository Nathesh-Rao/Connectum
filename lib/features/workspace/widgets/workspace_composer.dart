import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../conversation/widgets/commands_panel.dart';
import '../../conversation/widgets/conversation_composer.dart';
import '../../forms/widgets/forms_picker_sheet.dart';
import '../workspace_controller.dart';

/// The workspace composer: `#` opens the commands list, `@name text` messages
/// that person, and any other text is not sent (a hint says what to type).
/// The forms button works as everywhere else.
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
                    minLines: 1,
                    maxLines: 5,
                    minHeight: AppSpacing.composerButton,
                    horizontalPadding: AppSpacing.xxs,
                    fillColor: Colors.transparent,
                    hasFocusRing: false,
                    borderColor: Colors.transparent,
                    borderRadius: BorderRadius.zero,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    onChanged: c.onChanged,
                  ),
                ),
                Obx(
                  () => ComposerSendButton(
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
            child: Text(hint, style: AppText.caption),
          );
        }),
      ],
    );
  }
}
