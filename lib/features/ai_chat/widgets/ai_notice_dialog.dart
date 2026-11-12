import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';

/// The confirm-style dialog of the AI: a tinted icon, a title, a text and one
/// OK button, or with [confirmLabel] a Cancel and a confirm button.
class AiNoticeDialog extends StatelessWidget {
  const AiNoticeDialog({
    super.key,
    required this.title,
    required this.text,
    this.confirmLabel,
    this.preview,
  });

  final String title;
  final String text;
  final String? confirmLabel;

  /// Text shown in a box under [text], exactly as it will be posted.
  final String? preview;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String text,
  }) => showDialog<void>(
    context: context,
    barrierColor: AppColors.sheetBackdrop,
    builder: (_) => AiNoticeDialog(title: title, text: text),
  );

  /// True when the person taps [confirmLabel], false on Cancel or a tap
  /// outside.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String text,
    required String confirmLabel,
    String? preview,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierColor: AppColors.sheetBackdrop,
        builder: (_) => AiNoticeDialog(
          title: title,
          text: text,
          confirmLabel: confirmLabel,
          preview: preview,
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.violetTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 28,
                  color: AppColors.violet,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, textAlign: TextAlign.center, style: AppText.subtitle),
            if (text.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                text,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: AppColors.muted),
              ),
            ],
            if (preview != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                constraints: const BoxConstraints(maxHeight: 240),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.cardAll,
                  border: Border.all(color: AppColors.line),
                ),
                child: SingleChildScrollView(
                  child: Text(preview!, style: AppText.readable),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (confirmLabel == null)
              AppButton.primary(
                label: 'OK',
                isCentered: true,
                onPressed: () => Navigator.of(context).pop(),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: AppButton.secondary(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: AppButton.primary(
                      label: confirmLabel!,
                      isCentered: true,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
