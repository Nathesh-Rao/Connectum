import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';

/// "Old log file found". True: delete it and start a new one. False: keep it
/// and add to it. Null: dismissed, so logging stays off.
class OldLogDialog extends StatelessWidget {
  const OldLogDialog({super.key, required this.fileName});

  final String fileName;

  static Future<bool?> ask(BuildContext context, String fileName) =>
      showDialog<bool>(
        context: context,
        barrierColor: AppColors.sheetBackdrop,
        builder: (_) => OldLogDialog(fileName: fileName),
      );

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
          const Text('Old log file found', style: AppText.heading),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Delete the old log file ($fileName) and start a new one? '
            'Choose No to keep adding to it.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton.primary(
            label: 'Yes, delete',
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.text(
            label: 'No, keep it',
            tone: AppTextButtonTone.ink,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    ),
  );
}
