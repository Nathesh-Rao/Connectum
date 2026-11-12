import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/e2e/e2e_texts.dart';

/// The quiet line under the header while this phone cannot be set up because
/// the device list is full. The sheet itself opens once; this stays.
class DeviceLimitBanner extends StatelessWidget {
  const DeviceLimitBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(left: AppSpacing.page),
    decoration: const BoxDecoration(
      color: AppColors.primarySoft,
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock_outline, size: 16, color: AppColors.primaryBright),
        const SizedBox(width: AppSpacing.xs),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(E2eTexts.limitBanner, style: AppText.caption),
          ),
        ),
        AppButton.text(
          label: E2eTexts.limitSeeDevices,
          tone: AppTextButtonTone.accent,
          onPressed: onTap,
        ),
      ],
    ),
  );
}
