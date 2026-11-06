import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// The tint of a pill: the selected one is filled with the strong colour, the
/// others are tinted.
enum AppPillKind {
  neutral(AppColors.sage, AppColors.ink, AppColors.ink),
  accent(AppColors.accentTint, AppColors.accentInk, AppColors.accent),
  sand(AppColors.sand, AppColors.accentInk, AppColors.accentInk),
  success(AppColors.yesFill, AppColors.yesText, AppColors.yesDot),
  calm(AppColors.noFill, AppColors.noText, AppColors.muted);

  const AppPillKind(this.tint, this.ink, this.fill);

  final Color tint;
  final Color ink;
  final Color fill;
}

/// [compact] is the smaller pill of the Chats filters.
enum AppPillSize { regular, compact }

class AppPill {
  const AppPill({
    required this.label,
    this.count = 0,
    this.kind = AppPillKind.neutral,
  });

  final String label;

  /// Shown after the label when above zero.
  final int count;
  final AppPillKind kind;
}

/// Coloured pills in one horizontally scrollable row, for a set that is not
/// known until the data is. Replaces the tab bars and the underline filters.
class AppPillBar extends StatelessWidget {
  const AppPillBar({
    super.key,
    required this.pills,
    required this.selected,
    required this.onSelected,
    this.size = AppPillSize.regular,
    this.gap,
  });

  final List<AppPill> pills;
  final AppPillSize size;
  final int selected;
  final ValueChanged<int> onSelected;

  /// Horizontal gap between pills; the size's default when null.
  final double? gap;

  static const double _height = 34;

  @override
  Widget build(BuildContext context) {
    final isCompact = size == AppPillSize.compact;
    return SizedBox(
      height: isCompact
          ? AppSpacing.compactPillHeight
          : AppSpacing.minTapTarget,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < pills.length; i++) ...[
              if (i > 0)
                SizedBox(
                  width:
                      gap ??
                      (isCompact ? AppSpacing.compactPillGap : AppSpacing.xs),
                ),
              _PillButton(
                pill: pills[i],
                size: size,
                isSelected: i == selected,
                onTap: () => onSelected(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.pill,
    required this.size,
    required this.isSelected,
    required this.onTap,
  });

  final AppPill pill;
  final AppPillSize size;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = pill.kind;
    final isCompact = size == AppPillSize.compact;
    final ink = isSelected ? AppColors.background : kind.ink;
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: isCompact
              ? AppSpacing.compactPillHeight
              : AppSpacing.minTapTarget,
          child: Align(
            child: AnimatedContainer(
              duration: AppDurations.fast,
              curve: AppCurves.out,
              height: isCompact
                  ? AppSpacing.compactPillHeight
                  : AppPillBar._height,
              padding: EdgeInsets.symmetric(
                horizontal: isCompact
                    ? AppSpacing.compactPillPaddingX
                    : AppSpacing.sm,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? kind.fill : kind.tint,
                borderRadius: AppRadius.pillAll,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pill.label,
                    maxLines: 1,
                    softWrap: false,
                    style:
                        (isCompact
                                ? AppText.pillCompact
                                : AppText.readableStrong)
                            .copyWith(color: ink),
                  ),
                  if (pill.count > 0) ...[
                    SizedBox(
                      width: isCompact
                          ? AppSpacing.compactPillCountGap
                          : AppSpacing.xxs + 2,
                    ),
                    Text(
                      pill.count > 99 ? '99+' : '${pill.count}',
                      style: AppText.caption.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
