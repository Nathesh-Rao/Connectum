import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// A caption above its value, with a hairline between rows, for a detail
/// sheet.
class AppDetailRow extends StatelessWidget {
  const AppDetailRow({
    super.key,
    required this.caption,
    required this.value,
    this.valueColor = AppColors.ink,
    this.hasDivider = true,
  });

  final String caption;
  final String value;
  final Color valueColor;
  final bool hasDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: hasDivider
            ? const Border(top: BorderSide(color: AppColors.line))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: AppText.readable),
          const SizedBox(height: AppSpacing.xxs),
          Text(value, style: AppText.body.copyWith(color: valueColor)),
        ],
      ),
    );
  }
}
