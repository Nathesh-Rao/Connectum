import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../data/repositories/attachment_repository.dart';
import '../conversation_controller.dart';

/// "Photo library", "Camera" and "Document".
class AttachSheet extends StatelessWidget {
  const AttachSheet({super.key, required this.controller});

  final ConversationController controller;

  static Future<void> show(
    BuildContext context,
    ConversationController controller,
  ) => AppBottomSheet.show<void>(
    context,
    title: 'Attach',
    child: AttachSheet(controller: controller),
  );

  @override
  Widget build(BuildContext context) {
    void choose(AttachSource source) {
      Navigator.of(context).pop();
      controller.attach(source);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppListRow(
          title: 'Photo library',
          minHeight: AppSpacing.settingRowHeight,
          leading: const Icon(
            Icons.photo_library_outlined,
            size: 20,
            color: AppColors.muted,
          ),
          onTap: () => choose(AttachSource.library),
        ),
        AppListRow(
          title: 'Camera',
          minHeight: AppSpacing.settingRowHeight,
          leading: const Icon(
            Icons.photo_camera_outlined,
            size: 20,
            color: AppColors.muted,
          ),
          onTap: () => choose(AttachSource.camera),
        ),
        AppListRow(
          title: 'Document',
          minHeight: AppSpacing.settingRowHeight,
          leading: const Icon(
            Icons.description_outlined,
            size: 20,
            color: AppColors.muted,
          ),
          onTap: () => choose(AttachSource.document),
        ),
      ],
    );
  }
}
