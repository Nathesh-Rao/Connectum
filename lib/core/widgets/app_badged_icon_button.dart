import 'package:flutter/material.dart';

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
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;

  /// Nothing is shown at zero; 99+ is the cap.
  final int count;

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
