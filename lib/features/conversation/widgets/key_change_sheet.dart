import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/e2e/e2e_models.dart';
import '../conversation_controller.dart';

/// Shown when a person's security key changed. Sending to them stays blocked
/// until "Trust new key" is tapped, which pins the keys listed here.
class KeyChangeSheet extends StatelessWidget {
  const KeyChangeSheet({
    super.key,
    required this.controller,
    required this.review,
  });

  final ConversationController controller;
  final E2eKeyReview review;

  /// Reads the keys, then opens the sheet; nothing opens if they cannot be read.
  static Future<void> open(
    BuildContext context,
    ConversationController controller,
  ) async {
    final review = await controller.loadKeyReview();
    if (review == null || !context.mounted) return;
    await AppBottomSheet.show<void>(
      context,
      title: 'Security key changed',
      child: KeyChangeSheet(controller: controller, review: review),
    );
    await controller.recheckGate();
  }

  @override
  Widget build(BuildContext context) {
    final changed = review.changed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          changed.isEmpty
              ? "The keys match what this phone saw before, so there is nothing to trust. Try sending again."
              : "${review.user}'s device keys are different from the ones this phone saw first. "
                    'This happens when they set up a new browser or phone, but it could also be someone else. '
                    'Compare the safety number with ${review.user} in person or by phone before you trust it.',
          style: AppText.readable,
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Safety number', style: AppText.label),
        const SizedBox(height: AppSpacing.xxs),
        Text(review.safetyNumber, style: AppText.idValue),
        for (final c in changed) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            '${c.user}: ${c.device.label.isEmpty ? 'a device' : c.device.label} '
            '(${c.device.id.substring(0, c.device.id.length < 8 ? c.device.id.length : 8)})',
            style: AppText.caption.copyWith(color: AppColors.muted),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (changed.isNotEmpty)
          AppButton.primary(
            label: 'Trust new key',
            isCentered: true,
            onPressed: () async {
              await controller.trustKey(review);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        const SizedBox(height: AppSpacing.xs),
        AppButton.text(
          label: changed.isEmpty ? 'Close' : 'Not now',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
