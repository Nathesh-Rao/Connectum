import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';

/// One chip of an [InboxChipBar]: an id (for its key), its words and what its
/// × does.
class InboxChipData {
  const InboxChipData({
    required this.id,
    required this.label,
    required this.onRemove,
  });

  final String id;
  final String label;
  final VoidCallback onRemove;
}

/// The row of selected filters under the tab bar, shared by Records and
/// Approvals: removable chips (label and ×) in a sideways list. Nothing at all
/// (no "All" chip) when [chips] is empty.
class InboxChipBar extends StatelessWidget {
  const InboxChipBar({
    super.key,
    required this.chips,
    this.keyPrefix = 'inbox',
  });

  final List<InboxChipData> chips;

  /// The chips' keys are `<prefix>-selected-<id>`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppDurations.fast,
      curve: AppCurves.out,
      alignment: Alignment.topCenter,
      child: chips.isEmpty
          ? const SizedBox(width: double.infinity)
          : SizedBox(
              key: ValueKey('$keyPrefix-chip-bar'),
              height: AppSpacing.inboxChipHeight + AppSpacing.sm * 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: AppSpacing.page,
                  ),
                  children: [
                    for (final s in chips) ...[
                      _RemovableChip(
                        key: ValueKey('$keyPrefix-selected-${s.id}'),
                        label: s.label,
                        onRemove: s.onRemove,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({
    super.key,
    required this.label,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        label: 'Remove $label',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRemove,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.inboxChipHeight,
              maxWidth: AppSpacing.inboxChipMaxWidth,
            ),
            padding: const EdgeInsetsDirectional.only(
              start: AppSpacing.sm,
              end: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: AppRadius.pillAll,
              border: Border.all(color: AppColors.primaryBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.readableStrong.copyWith(
                      color: AppColors.primaryStrong,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.primaryStrong,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
