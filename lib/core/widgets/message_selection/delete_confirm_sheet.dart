import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import '../app_bottom_sheet.dart';
import '../app_button.dart';

/// "Delete?" with Cancel, for one or several selected messages. [onDelete]
/// returns a plain-words problem, or null when it worked (the sheet closes).
class DeleteConfirmSheet extends StatelessWidget {
  const DeleteConfirmSheet({
    super.key,
    required this.text,
    required this.onDelete,
  });

  final String text;
  final Future<String?> Function() onDelete;

  /// True when the messages were deleted.
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String text,
    required Future<String?> Function() onDelete,
  }) => AppBottomSheet.show<bool>(
    context,
    title: title,
    child: DeleteConfirmSheet(text: text, onDelete: onDelete),
  );

  @override
  Widget build(BuildContext context) {
    final problem = RxnString();
    final isBusy = false.obs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, style: AppText.readable),
        Obx(
          () => problem.value == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(problem.value!, style: AppText.error),
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Obx(
          () => AppButton.primary(
            label: 'Delete',
            isLoading: isBusy.value,
            onPressed: () async {
              isBusy.value = true;
              try {
                final result = await onDelete();
                if (result == null) {
                  if (context.mounted) Navigator.of(context).pop(true);
                } else {
                  problem.value = result;
                }
              } finally {
                isBusy.value = false;
              }
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
