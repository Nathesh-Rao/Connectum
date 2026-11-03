import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

class AppStatusPill extends StatelessWidget {
  const AppStatusPill({super.key, required this.isYes});

  final bool isYes;

  @override
  Widget build(BuildContext context) {
    final text = isYes ? AppColors.yesText : AppColors.noText;
    return Container(
      height: AppSpacing.statusPillHeight,
      padding: const EdgeInsets.only(left: AppSpacing.xs, right: 10),
      decoration: BoxDecoration(
        color: isYes ? AppColors.yesFill : AppColors.noFill,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isYes ? AppColors.yesDot : AppColors.noDot,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isYes ? 'Yes' : 'No',
            style: AppText.readableStrong.copyWith(color: text),
          ),
        ],
      ),
    );
  }
}
