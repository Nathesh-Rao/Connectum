import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import '../notification_texts.dart';

/// The priority of a feed item as a label and a colour. Low is the default
/// of nearly every item, so it shows nothing.
class FeedPriorityPill extends StatelessWidget {
  const FeedPriorityPill({super.key, required this.priority});

  final String priority;

  /// The one mapping of a priority to its tone: the pill and the tile's
  /// leading icon both use it. Null for low and unknown priorities.
  static AppTone? toneOf(String priority) => switch (priority) {
    'high' => AppTones.red,
    'medium' => AppTones.violet,
    'resolved' => AppTones.green,
    _ => null,
  };

  static String? _labelOf(String priority) => switch (priority) {
    'high' => NotificationTexts.priorityHigh,
    'medium' => NotificationTexts.priorityMedium,
    'resolved' => NotificationTexts.priorityResolved,
    _ => null,
  };

  static (String, AppTone)? of(String priority) {
    final label = _labelOf(priority);
    final tone = toneOf(priority);
    return label == null || tone == null ? null : (label, tone);
  }

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
