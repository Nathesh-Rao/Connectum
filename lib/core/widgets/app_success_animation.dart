import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Plays the success check once at its own frame rate and holds the finished
/// check. The file fades everything out over its last 13 frames, so the hold
/// frame is the last one before that fade. Reduced motion shows the hold
/// frame straight away.
class AppSuccessAnimation extends StatefulWidget {
  const AppSuccessAnimation({
    super.key,
    this.size = AppSpacing.successAnimation,
  });

  static const asset = 'assets/lottie/state_success_blue.json';
  static const holdFrame = 49.0;

  final double size;

  @override
  State<AppSuccessAnimation> createState() => _AppSuccessAnimationState();
}

class _AppSuccessAnimationState extends State<AppSuccessAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onLoaded(LottieComposition composition) {
    final hold =
        (AppSuccessAnimation.holdFrame - composition.startFrame) /
        composition.durationFrames;
    _controller.duration = composition.duration;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = hold;
    } else {
      _controller.animateTo(
        hold,
        duration: composition.duration * hold,
        curve: Curves.linear,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Lottie.asset(
          AppSuccessAnimation.asset,
          controller: _controller,
          frameRate: FrameRate.composition,
          fit: BoxFit.contain,
          onLoaded: _onLoaded,
          errorBuilder: (context, error, stack) => Center(
            child: Container(
              width: AppSpacing.checkBadge,
              height: AppSpacing.checkBadge,
              decoration: const BoxDecoration(
                color: AppColors.primaryTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 32, color: AppColors.primaryBright),
            ),
          ),
        ),
      ),
    );
  }
}
