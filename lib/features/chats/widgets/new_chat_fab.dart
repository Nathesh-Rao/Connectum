import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_fab.dart';
import '../../../core/widgets/app_png_icon.dart';

/// The new chat button of the Chats tab. It slides down, shrinks and fades
/// out of the way while [isShown] is false or the keyboard is open, and cannot
/// be tapped or read by a screen reader then.
class NewChatFab extends StatelessWidget {
  const NewChatFab({
    super.key,
    required this.isShown,
    required this.isKeyboardOpen,
    required this.onPressed,
  });

  final bool isShown;

  /// Read above the screen's scaffold, which hides the keyboard inset from
  /// its body.
  final bool isKeyboardOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isVisible = isShown && !isKeyboardOpen;
    final isStill = MediaQuery.disableAnimationsOf(context);
    final duration = isStill ? Duration.zero : AppDurations.fab;
    final curve = isVisible ? Curves.easeOutCubic : Curves.easeInCubic;
    return ExcludeSemantics(
      excluding: !isVisible,
      child: IgnorePointer(
        ignoring: !isVisible,
        child: AnimatedSlide(
          duration: duration,
          curve: curve,
          offset: isVisible
              ? Offset.zero
              : const Offset(0, AppSpacing.fabHideShift / AppSpacing.fab),
          child: AnimatedScale(
            duration: duration,
            curve: curve,
            scale: isVisible ? 1 : 0.8,
            child: AnimatedOpacity(
              duration: duration,
              curve: curve,
              opacity: isVisible ? 1 : 0,
              child: AppFab(
                semanticLabel: 'New chat',
                onPressed: onPressed,
                child: AppPngIcon(
                  asset: AppIcons.home.newChat,
                  size: 24,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
