import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// AnimatedSize whose intrinsic height is its current animated height. A
/// parent that measures intrinsics (the scaffold's fill-remaining sliver) then
/// sizes itself to what is on screen, not to the final height, so a shrinking
/// section cannot overflow the page while it animates.
class AppAnimatedSize extends StatelessWidget {
  const AppAnimatedSize({
    super.key,
    required this.duration,
    required this.curve,
    required this.alignment,
    required this.child,
  });

  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animated = AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: alignment,
      child: child,
    );
    if (duration == Duration.zero) return animated;
    return _CurrentHeight(child: animated);
  }
}

class _CurrentHeight extends SingleChildRenderObjectWidget {
  const _CurrentHeight({required Widget child}) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCurrentHeight();
}

class _RenderCurrentHeight extends RenderProxyBox {
  double? _laidOutHeight;

  @override
  void performLayout() {
    super.performLayout();
    _laidOutHeight = size.height;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _laidOutHeight ?? super.computeMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _laidOutHeight ?? super.computeMaxIntrinsicHeight(width);
}
