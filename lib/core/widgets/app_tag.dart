import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

enum AppTagTone { accent, neutral, done }

/// A small rounded label: "Waiting for approval", a branch.
class AppTag extends StatelessWidget {
  const AppTag({
    super.key,
    required this.label,
    this.tone = AppTagTone.neutral,
    this.icon,
  });

  final String label;
  final AppTagTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = switch (tone) {
      AppTagTone.accent => AppColors.primaryStrong,
      AppTagTone.done => AppColors.yesText,
      AppTagTone.neutral => AppColors.noText,
    };
    final fill = switch (tone) {
      AppTagTone.accent => AppColors.primaryTint,
      AppTagTone.done => AppColors.yesFill,
      AppTagTone.neutral => AppColors.noFill,
    };
    return Container(
      height: AppSpacing.tagHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(
            child: Text(
              label,
              style: AppText.readableStrong.copyWith(color: ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
