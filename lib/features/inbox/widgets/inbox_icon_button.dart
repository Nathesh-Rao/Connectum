import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_inbox.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/widgets/app_unread_badge.dart';

/// A header button of the Inbox: a round tonal disc in a 44 dp tap target,
/// with a tooltip and a spoken label, and an optional count or dot.
class InboxIconButton extends StatelessWidget {
  const InboxIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.count = 0,
    this.isActive = false,
    this.tone = AppTones.blue,
  });

  /// The disc's own colours: a soft tint with a strong icon; filled when
  /// [isActive].
  final AppTone tone;

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Nothing is shown at zero; 99+ is the cap.
  final int count;

  /// The disc is filled (something is set).
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: AppInbox.hit,
            height: AppInbox.hit,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: AppDurations.fast,
                  curve: AppCurves.out,
                  width: AppInbox.disc,
                  height: AppInbox.disc,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? tone.strong : tone.tint,
                  ),
                  child: Icon(
                    icon,
                    size: AppInbox.discIcon,
                    color: isActive ? AppInbox.discActiveInk : tone.strong,
                  ),
                ),
                if (count > 0)
                  PositionedDirectional(
                    top: 0,
                    end: 0,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.white,
                            width: AppSpacing.xxs / 2,
                          ),
                        ),
                        child: AppUnreadBadge(
                          label: count > 99 ? '99+' : '$count',
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
