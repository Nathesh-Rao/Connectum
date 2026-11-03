import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// A thin determinate bar, [value] from 0 to 1.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: AppRadius.pillAll,
    child: SizedBox(
      height: AppSpacing.progressHeight,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: AppDurations.fast,
        curve: AppCurves.out,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: AppSpacing.progressHeight,
          backgroundColor: AppColors.line,
          color: AppColors.accent,
        ),
      ),
    ),
  );
}
