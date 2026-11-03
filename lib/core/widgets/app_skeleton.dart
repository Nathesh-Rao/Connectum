import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';

/// One shared pulse for every placeholder under it, so a screen of skeleton
/// rows runs a single animation.
class AppSkeletonScope extends StatefulWidget {
  const AppSkeletonScope({super.key, required this.child});

  final Widget child;

  static Animation<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PulseInherited>()!.animation;

  @override
  State<AppSkeletonScope> createState() => _AppSkeletonScopeState();
}

class _AppSkeletonScopeState extends State<AppSkeletonScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.spin,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PulseInherited(
    animation: CurvedAnimation(parent: _controller, curve: AppCurves.inOut),
    child: widget.child,
  );
}

class _PulseInherited extends InheritedWidget {
  const _PulseInherited({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_PulseInherited old) => animation != old.animation;
}

class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = AppRadius.xs,
    this.isCircle = false,
  });

  final double? width;
  final double height;
  final double radius;
  final bool isCircle;

  @override
  Widget build(BuildContext context) {
    final pulse = AppSkeletonScope.of(context);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(pulse),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.avatarBg,
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isCircle
              ? null
              : BorderRadius.all(Radius.circular(radius)),
        ),
      ),
    );
  }
}
