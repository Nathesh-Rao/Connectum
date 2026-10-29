import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

enum AppTransitionKind { push, tab, fade, intro, enter, slideUp }

class AppTransition extends CustomTransition {
  AppTransition(this.kind);

  final AppTransitionKind kind;

  Duration get duration => switch (kind) {
    AppTransitionKind.push => AppDurations.page,
    AppTransitionKind.tab => AppDurations.base,
    AppTransitionKind.fade => AppDurations.base,
    AppTransitionKind.intro => AppDurations.slow,
    AppTransitionKind.enter => AppDurations.slow,
    AppTransitionKind.slideUp => AppDurations.slow,
  };

  @override
  Widget buildTransition(
    BuildContext context,
    Curve? curve,
    Alignment? alignment,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final isReduced = MediaQuery.disableAnimationsOf(context);
    final primary = CurvedAnimation(
      parent: animation,
      curve: AppCurves.out,
      reverseCurve: AppCurves.out,
    );
    if (isReduced || kind == AppTransitionKind.fade) {
      return FadeTransition(opacity: primary, child: child);
    }
    return switch (kind) {
      AppTransitionKind.push => _push(primary, secondaryAnimation, child),
      AppTransitionKind.tab => _rise(primary, AppDistances.tab, child),
      AppTransitionKind.enter => _rise(primary, AppDistances.enter, child),
      AppTransitionKind.slideUp => _slideUp(animation, child),
      _ => FadeTransition(
        opacity: primary,
        child: ScaleTransition(
          scale: Tween(
            begin: AppDistances.introScale,
            end: 1.0,
          ).animate(primary),
          child: child,
        ),
      ),
    };
  }

  Widget _push(
    Animation<double> primary,
    Animation<double> secondary,
    Widget child,
  ) {
    final secondaryCurved = CurvedAnimation(
      parent: secondary,
      curve: AppCurves.out,
      reverseCurve: AppCurves.out,
    );
    final covered = Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: secondaryCurved,
              builder: (_, _) => ColoredBox(
                color: AppColors.scrim.withValues(
                  alpha: AppDistances.scrimOpacity * secondaryCurved.value,
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(primary),
      child: SlideTransition(
        position: Tween(
          begin: Offset.zero,
          end: const Offset(-AppDistances.parallax, 0),
        ).animate(secondaryCurved),
        child: covered,
      ),
    );
  }

  /// A panel rising from the bottom over a fading scrim; the screen under it
  /// stays where it is.
  Widget _slideUp(Animation<double> animation, Widget child) {
    final scrim = CurvedAnimation(parent: animation, curve: AppCurves.out);
    final panel = CurvedAnimation(
      parent: animation,
      curve: AppCurves.sheet,
      reverseCurve: AppCurves.out,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(
          opacity: scrim,
          child: const ColoredBox(color: AppColors.sheetBackdrop),
        ),
        SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(panel),
          child: child,
        ),
      ],
    );
  }

  Widget _rise(Animation<double> primary, double distance, Widget child) {
    return FadeTransition(
      opacity: primary,
      child: AnimatedBuilder(
        animation: primary,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, (1 - primary.value) * distance),
          child: child,
        ),
        child: child,
      ),
    );
  }
}
