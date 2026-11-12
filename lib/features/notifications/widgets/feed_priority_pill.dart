import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../notification_texts.dart';

/// The priority of a feed item as a label and a colour. Low is the default
/// of nearly every item, so it shows nothing.
class FeedPriorityPill extends StatelessWidget {
  const FeedPriorityPill({super.key, required this.priority});

  final String priority;

  static (String, AppTone)? of(String priority) => switch (priority) {
    'high' => (NotificationTexts.priorityHigh, AppTones.red),
    'medium' => (NotificationTexts.priorityMedium, AppTones.violet),
    'resolved' => (NotificationTexts.priorityResolved, AppTones.green),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final shown = of(priority);
    if (shown == null) return const SizedBox.shrink();
    final (label, tone) = shown;
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: Container(
        height: AppSpacing.priorityPillHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color: tone.tint,
          borderRadius: AppRadius.pillAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppText.label.copyWith(color: tone.strong, height: 1),
            ),
          ],
        ),
      ),
    );
  }
}
