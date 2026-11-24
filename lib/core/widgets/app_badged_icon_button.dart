import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';
import 'app_unread_badge.dart';

/// An icon button with a count painted over its corner. The hit area is the
/// full [AppSpacing.badgedIconHit] square and the badge ignores pointers, so
/// a tap on the badge is a tap on the button.
class AppBadgedIconButton extends StatelessWidget {
  const AppBadgedIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.count = 0,
    this.hasDot = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;

  /// Nothing is shown at zero; 99+ is the cap.
  final int count;

  /// A small dot in the corner instead of a number.
  final bool hasDot;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox(
        width: AppSpacing.badgedIconHit,
        height: AppSpacing.badgedIconHit,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            AppButton.icon(
              icon: icon,
              semanticLabel: semanticLabel,
              onPressed: onPressed,
            ),
            if (hasDot && count <= 0)
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: IgnorePointer(
                  child: Container(
                    key: const ValueKey('badge-dot'),
                    width: AppSpacing.xs,
                    height: AppSpacing.xs,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            if (count > 0)
              Positioned(
                top: AppSpacing.xxs,
                right: AppSpacing.xxs,
                child: IgnorePointer(
                  child: AppUnreadBadge(label: count > 99 ? '99+' : '$count'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
