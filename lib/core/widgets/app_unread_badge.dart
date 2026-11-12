import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// The accent count on a row (grey when muted). It pops when the number
/// changes. 99+ is the cap.
class AppUnreadBadge extends StatelessWidget {
  const AppUnreadBadge({
    super.key,
    required this.label,
    this.isMuted = false,
    this.color = AppColors.primary,
  });

  /// The text to show: a number, or "99+" past the cap.
  final String label;

  /// A muted conversation keeps a count, in a quieter grey.
  final bool isMuted;

  /// The fill when not muted.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label unread',
      excludeSemantics: true,
      child: AnimatedSwitcher(
        duration: AppDurations.fast,
        switchInCurve: AppCurves.out,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Container(
          key: ValueKey(label),
          constraints: const BoxConstraints(
            minWidth: AppSpacing.unreadBadge,
            minHeight: AppSpacing.unreadBadge,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isMuted ? AppColors.noDot : color,
            borderRadius: BorderRadius.circular(AppSpacing.unreadBadge),
          ),
          child: Text(
            label,
            style: AppText.caption.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
