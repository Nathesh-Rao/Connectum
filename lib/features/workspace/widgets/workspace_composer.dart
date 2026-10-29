import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../conversation/widgets/conversation_composer.dart';
import '../../forms/widgets/forms_picker_sheet.dart';
import '../workspace_controller.dart';

/// The workspace has no free text: the field is off and says what to do. The
/// forms button works as everywhere else.
class WorkspaceComposer extends StatelessWidget {
  const WorkspaceComposer({super.key, required this.controller});

  static const hint = 'Pick a form or type # for commands';

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => Padding(
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
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.bubble)),
      ),
      child: Row(
        children: [
          FormsButton(
            onTap: () => FormsPickerSheet.show(context, controller.picker),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.input.copyWith(color: AppColors.muted),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
