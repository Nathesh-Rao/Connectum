import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_avatar.dart';

/// The first message of the workspace: a greeting from the workspace's own
/// bot avatar. It is built here, not delivered by the server.
class WorkspaceWelcome extends StatelessWidget {
  const WorkspaceWelcome({super.key, required this.text});

  static const sender = 'Connectum Workspace';

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.bubbleGap),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const AppAvatar(name: 'WS', size: 32),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.bubblePadX,
              vertical: AppSpacing.bubblePadY,
            ),
            decoration: const BoxDecoration(
              color: AppColors.bubbleIn,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppRadius.bubble),
                topRight: Radius.circular(AppRadius.bubble),
                bottomRight: Radius.circular(AppRadius.bubble),
                bottomLeft: Radius.circular(AppRadius.bubbleTail),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender,
                  style: AppText.label.copyWith(color: AppColors.accentInk),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(text, style: AppText.message),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
