import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';

/// A question with two answers in a bottom sheet; closing it is the cancel
/// answer. True when [confirm] is chosen.
class SvConfirmSheet {
  SvConfirmSheet._();

  static Future<bool> ask(
    BuildContext context, {
    required String title,
    required String message,
    required String confirm,
    required String cancel,
    bool isDanger = false,
  }) async {
    final r = await AppBottomSheet.show<bool>(
      context,
      title: title,
      child: Builder(
        builder: (sheet) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: AppText.body),
            const SizedBox(height: AppSpacing.md),
            if (isDanger)
              AppButton.secondary(
                label: confirm,
                isDanger: true,
                onPressed: () => Navigator.of(sheet).pop(true),
              )
            else
              AppButton.primary(
                label: confirm,
                onPressed: () => Navigator.of(sheet).pop(true),
              ),
            const SizedBox(height: AppSpacing.xs),
            AppButton.text(
              label: cancel,
              onPressed: () => Navigator.of(sheet).pop(false),
            ),
          ],
        ),
      ),
    );
    return r ?? false;
  }
}
