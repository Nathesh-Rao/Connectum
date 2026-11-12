import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_png_icon.dart';
import '../../../core/widgets/app_row_highlight.dart';

/// The pinned My Work Space row above the conversations. It is not a
/// conversation, so it is never archived and always comes first.
class WorkspaceRow extends StatelessWidget {
  const WorkspaceRow({super.key, required this.onTap});

  final VoidCallback onTap;

  static const preview = "Type '#' for commands, automated tasks & alerts";

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'My Work Space, pinned',
      excludeSemantics: true,
      child: AppRowHighlight(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.chatRowHeight,
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              Container(
                width: AppSpacing.avatar,
                height: AppSpacing.avatar,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primaryTintStrong),
                ),
                child: AppPngIcon(
                  asset: AppIcons.home.workSpace,
                  size: 22,
                  color: AppColors.primaryBright,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('My Work Space', style: AppText.rowTitle),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowCaption,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.rowChevron,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
