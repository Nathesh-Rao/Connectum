import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// Replaces a widget that failed to build, in release builds only. Shows no
/// error text.
class AppFriendlyError extends StatelessWidget {
  const AppFriendlyError({super.key});

  static const title = 'Something went wrong';
  static const line = 'Please try again.';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceSubtle,
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: AppColors.line),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: AppText.bodyStrong,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppSpacing.xxs),
              Text(line, style: AppText.readable, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
