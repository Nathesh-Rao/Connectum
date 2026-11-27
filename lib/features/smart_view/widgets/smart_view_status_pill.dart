import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';

/// A status as a soft tinted pill with a leading dot, shared by the cards and
/// the table. Words the app already colours (approved, declined, waiting,
/// open, in progress, done) keep their tone; any other word is a neutral
/// blue-grey, never a random colour.
class SmartViewStatusPill extends StatelessWidget {
  const SmartViewStatusPill({
    super.key,
    required this.label,
    this.isCompact = false,
  });

  final String label;

  /// The smaller phone-scale pill used in cards and the table.
  final bool isCompact;

  static AppTone toneOf(String label) {
    final t = label.trim().toLowerCase();
    if (const {
      'approved',
      'done',
      'completed',
      'closed',
      'resolved',
    }.contains(t)) {
      return AppTones.green;
    }
    if (const {'declined', 'rejected', 'cancelled', 'canceled'}.contains(t)) {
      return AppTones.red;
    }
    if (const {'waiting for approval', 'pending', 'on hold'}.contains(t)) {
      return AppTones.violet;
    }
    if (const {'open', 'in progress', 'new', 'assigned'}.contains(t)) {
      return AppTones.blue;
    }
    return AppTones.slate;
  }

  @override
  Widget build(BuildContext context) {
    final tone = toneOf(label);
    if (isCompact) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSv.pillPadX,
          vertical: AppSv.pillPadY,
        ),
        decoration: BoxDecoration(
          color: tone.tint,
          borderRadius: AppRadius.pillAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: tone.solid,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(
                width: AppSv.pillDot,
                height: AppSv.pillDot,
              ),
            ),
            const SizedBox(width: AppSpacing.xxs + 2),
            Text(
              label,
              style: AppSv.pillText.copyWith(color: tone.strong),
              maxLines: 1,
              softWrap: false,
            ),
          ],
        ),
      );
    }
    return Container(
      height: AppSpacing.statusPillHeight,
      padding: const EdgeInsets.only(left: AppSpacing.xs, right: AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: tone.solid,
              shape: BoxShape.circle,
            ),
            child: const SizedBox(width: 6, height: 6),
          ),
          const SizedBox(width: AppSpacing.xxs + 2),
          Text(
            label,
            style: AppText.readableStrong.copyWith(color: tone.strong),
            maxLines: 1,
            softWrap: false,
          ),
        ],
      ),
    );
  }
}
