import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../profile_controller.dart';

class LogoutSheet extends StatelessWidget {
  const LogoutSheet({super.key, required this.controller, required this.unsent});

  final ProfileController controller;
  final int unsent;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "You'll need to sign in again. Your encryption keys stay on this phone.",
          style: AppText.body,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Saved chats and submissions on this phone are removed.',
          style: AppText.readable,
        ),
        if (unsent > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            unsent == 1
                ? '1 message has not been sent yet and will be lost.'
                : '$unsent messages have not been sent yet and will be lost.',
            style: AppText.error,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Obx(
          () => AppButton.secondary(
            label: 'Log out',
            leadingIcon: Icons.logout,
            isDanger: true,
            isLoading: c.isLoggingOut.value,
            onPressed: c.logOut,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Obx(
          () => AppButton.text(
            label: 'Cancel',
            tone: AppTextButtonTone.ink,
            onPressed: c.isLoggingOut.value ? null : () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}
