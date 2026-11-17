import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';

/// A compact tappable pill: a label and, when it opens a menu, a chevron.
class SvPill extends StatelessWidget {
  const SvPill({
    super.key,
    required this.label,
    required this.onTap,
    this.hasChevron = true,
    this.isActive = false,
    this.maxWidth = 160,
  });

  final String label;
  final VoidCallback? onTap;
  final bool hasChevron;
  final bool isActive;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: AppSpacing.pillTall,
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: isActive ? AppColors.violetTint : AppColors.fill,
                borderRadius: AppRadius.pillAll,
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
                        color: isActive
                            ? AppColors.violetStrong
                            : AppColors.ink,
                      ),
                    ),
                  ),
                  if (hasChevron) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    Icon(
                      Icons.expand_more,
                      size: AppSpacing.pillChevron,
                      color: AppColors.muted,
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

/// A round icon action with a 48 dp tap target and a smaller visible circle.
class SvIconAction extends StatelessWidget {
  const SvIconAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: AppSpacing.badgedIconHit,
          height: AppSpacing.badgedIconHit,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: AppDurations.smartChip,
                  width: AppSpacing.pillTall,
                  height: AppSpacing.pillTall,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.violetTint : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: AppSpacing.popupMenuIcon,
                    color: isActive ? AppColors.violetStrong : AppColors.ink,
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    right: -AppSpacing.xxs,
                    top: -AppSpacing.xxs,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: AppSpacing.unreadBadge - 4,
                        minHeight: AppSpacing.unreadBadge - 4,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.violet,
                        borderRadius: AppRadius.pillAll,
                      ),
                      child: Text(
                        '$badge',
                        style: AppText.caption.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
