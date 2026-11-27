import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/smart_view/engine/sv_engine.dart';
import '../../../data/smart_view/sv_team.dart';
import '../smart_view_controller.dart';
import 'sv_sort_sheet.dart';

/// The active filters and the sort, one removable chip each, in a row that
/// scrolls sideways. Hidden (it collapses) when the query holds neither.
class SvChipsStrip extends StatelessWidget {
  const SvChipsStrip({super.key, required this.controller});

  final SmartViewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final q = c.query.value;
      final cols = c.columns?.columns ?? const [];
      String labelOf(String key) {
        for (final x in cols) {
          if (x.key == key) return x.label;
        }
        return key;
      }

      final conditions = q.activeConditions;
      final sortLabel = q.sortKey == null ? null : labelOf(q.sortKey!);
      final hasAny = conditions.isNotEmpty || sortLabel != null;
      return AnimatedSize(
        duration: AppDurations.smartControls,
        curve: AppCurves.out,
        alignment: Alignment.topCenter,
        child: !hasAny
            ? const SizedBox(width: double.infinity)
            : SizedBox(
                height: AppSpacing.chipStripHeight,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  children: [
                    for (final cond in conditions)
                      _ChipIn(
                        key: ValueKey('sv-chip-${cond.hashCode}'),
                        child: _Chip(
                          label: SvTeam.isTeamLine(cond)
                              ? SvTeam.chipText(cond, c.teamNameOf)
                              : SvEngine.chipText(cond, labelOf(cond.col)),
                          onRemove: () => c.removeCondition(cond),
                        ),
                      ),
                    if (sortLabel != null)
                      _ChipIn(
                        key: const ValueKey('sv-chip-sort'),
                        child: _Chip(
                          label: sortLabel,
                          trailingArrow: q.isAscending,
                          onTap: c.flipSort,
                          onRemove: c.clearSort,
                        ),
                      ),
                    Center(
                      child: AppButton.text(
                        label: 'Clear',
                        onPressed: c.clearQuery,
                      ),
                    ),
                  ],
                ),
              ),
      );
    });
  }
}

class _ChipIn extends StatelessWidget {
  const _ChipIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppDurations.smartChip,
      curve: AppCurves.out,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale:
              AppDistances.chipPopScale + (1 - AppDistances.chipPopScale) * t,
          child: child,
        ),
      ),
      child: Center(child: child),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.onRemove,
    this.onTap,
    this.trailingArrow,
  });

  final String label;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  /// Non-null for the sort chip: true is ascending.
  final bool? trailingArrow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.violetTint,
          borderRadius: AppRadius.pillAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: SizedBox(
                  height: AppSpacing.pillTall,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.readableStrong.copyWith(
                            color: AppColors.violetStrong,
                          ),
                        ),
                      ),
                      if (trailingArrow != null) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        SvSortArrow(
                          isAscending: trailingArrow!,
                          color: AppColors.violetStrong,
                          size: AppSpacing.pillChevron,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Remove $label',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: const SizedBox(
                  width: AppSpacing.minTapTarget - 4,
                  height: AppSpacing.pillTall,
                  child: Icon(
                    Icons.close,
                    size: AppSpacing.pillChevron,
                    color: AppColors.violetStrong,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
