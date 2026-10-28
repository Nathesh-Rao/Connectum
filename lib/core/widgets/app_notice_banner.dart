import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_button.dart';

/// A dark banner for persistent notices that stay until dismissed (the
/// session notice, an error to read). Never for temporary feedback.
class AppNoticeBanner extends StatelessWidget {
  const AppNoticeBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.ink,
        borderRadius: AppRadius.controlAll,
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                message,
                style: AppText.readable.copyWith(color: AppColors.background),
              ),
            ),
          ),
          AppButton.icon(
            icon: Icons.close,
            semanticLabel: 'Dismiss',
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
