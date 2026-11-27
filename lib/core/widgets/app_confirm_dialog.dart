import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'app_button.dart';

/// A title, a message, a confirm button and a cancel button. [ask] answers
/// true only when the person confirmed.
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
    this.isDanger = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDanger;

  static Future<bool> ask(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Cancel',
    bool isDanger = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierColor: AppColors.sheetBackdrop,
        builder: (_) => AppConfirmDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          isDanger: isDanger,
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.white,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(AppSpacing.xl),
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.heading),
          const SizedBox(height: AppSpacing.sm),
          Text(message, style: AppText.body),
          const SizedBox(height: AppSpacing.lg),
          isDanger
              ? AppButton.secondary(
                  label: confirmLabel,
                  isDanger: true,
                  onPressed: () => Navigator.of(context).pop(true),
                )
              : AppButton.primary(
                  label: confirmLabel,
                  isCentered: true,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.text(
            label: cancelLabel,
            tone: AppTextButtonTone.ink,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    ),
  );
}
