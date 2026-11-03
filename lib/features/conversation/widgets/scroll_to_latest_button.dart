import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_unread_badge.dart';

/// Shown while the list is scrolled up: jumps to the newest message, with a
/// count of the messages that arrived meanwhile.
class ScrollToLatestButton extends StatelessWidget {
  const ScrollToLatestButton({
    super.key,
    required this.isVisible,
    required this.count,
    required this.onPressed,
  });

  final bool isVisible;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !isVisible,
      child: AnimatedScale(
        scale: isVisible ? 1 : 0.6,
        duration: AppDurations.fast,
        curve: AppCurves.out,
        child: AnimatedOpacity(
          opacity: isVisible ? 1 : 0,
          duration: AppDurations.fast,
          child: Semantics(
            button: true,
            label: count > 0
                ? 'Scroll to latest, $count new'
                : 'Scroll to latest',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onPressed,
              child: SizedBox(
                width: AppSpacing.scrollButton + 8,
                height: AppSpacing.scrollButton + 8,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: AppSpacing.scrollButton,
                      height: AppSpacing.scrollButton,
                      decoration: const BoxDecoration(
                        color: AppColors.background,
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.card,
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: AppColors.ink,
                      ),
                    ),
                    if (count > 0)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: AppUnreadBadge(
                          label: count > 99 ? '99+' : '$count',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
