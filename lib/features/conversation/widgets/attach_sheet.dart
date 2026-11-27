import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_sheet_header.dart';
import '../../../data/repositories/attachment_repository.dart';
import '../conversation_controller.dart';
import 'attach_circle_button.dart';

/// "Photo library", "Camera" and "Document" as three circles.
class AttachSheet extends StatelessWidget {
  const AttachSheet({super.key, required this.controller});

  final ConversationController controller;

  static Future<void> show(
    BuildContext context,
    ConversationController controller,
  ) => AppBottomSheet.showPinned<void>(
    context,
    child: AttachSheet(controller: controller),
  );

  @override
  Widget build(BuildContext context) {
    void choose(AttachSource source) {
      Navigator.of(context).pop();
      controller.attach(source);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSheetHeader(title: 'Attach', titleSize: 18),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            AttachCircleButton(
              icon: Icons.photo_library_outlined,
              label: 'Photo library',
              accent: AppColors.primaryBright,
              onTap: () => choose(AttachSource.library),
            ),
            AttachCircleButton(
              icon: Icons.photo_camera_outlined,
              label: 'Camera',
              accent: AppColors.violet,
              onTap: () => choose(AttachSource.camera),
            ),
            AttachCircleButton(
              icon: Icons.description_outlined,
              label: 'Document',
              accent: AppColors.yesDot,
              onTap: () => choose(AttachSource.document),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.xl + MediaQuery.paddingOf(context).bottom),
      ],
    );
  }
}
