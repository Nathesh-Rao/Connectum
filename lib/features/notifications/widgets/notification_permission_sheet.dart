import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../notification_texts.dart';

/// The short explainer before the system's notification prompt. Pops true on
/// "Allow", false otherwise.
class NotificationPermissionSheet extends StatelessWidget {
  const NotificationPermissionSheet({super.key});

  static Future<bool?> show(BuildContext context) => AppBottomSheet.show<bool>(
    context,
    title: NotificationTexts.permissionTitle,
    child: const NotificationPermissionSheet(),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(NotificationTexts.permissionBody, style: AppText.body),
        const SizedBox(height: AppSpacing.lg),
        AppButton.primary(
          label: NotificationTexts.permissionAllow,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton.text(
          label: NotificationTexts.permissionLater,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
