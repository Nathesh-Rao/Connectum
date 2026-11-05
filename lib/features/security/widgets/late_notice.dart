import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_highlight_text.dart';

/// A calm, non-blocking line: this phone was added after other devices, so
/// earlier messages wait until an older device shows them. [detail] says who
/// can, or that nobody was active and the recovery code is the way.
class LateNotice extends StatelessWidget {
  const LateNotice({
    super.key,
    required this.title,
    this.detail,
    this.values = const {},
  });

  final String title;
  final String? detail;
  final Map<String, String> values;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: const BoxDecoration(
      color: AppColors.accentSoft,
      borderRadius: AppRadius.mdAll,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.readableStrong),
        if (detail != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          AppHighlightText(detail!, values: values),
        ],
      ],
    ),
  );
}
