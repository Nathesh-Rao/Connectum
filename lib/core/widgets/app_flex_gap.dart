import 'package:flutter/widgets.dart';

/// Vertical space that shares the free height with its siblings in
/// proportion to [flex], but never goes below [min] (unless the screen is too
/// short) or above [max]. Only for a Column. Its intrinsic height is [min],
/// so a Column in an IntrinsicHeight is not stretched by the maximums.
class AppFlexGap extends StatelessWidget {
  const AppFlexGap({
    super.key,
    required this.flex,
    this.min = 0,
    this.max = 1000,
  });

  /// The measured gap on the prototype frame; used as the flex weight.
  final double flex;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      flex: flex.round(),
      child: _Gap(min: min, max: max),
    );
  }
}

class _Gap extends LeafRenderObjectWidget {
  const _Gap({required this.min, required this.max});

  final double min;
  final double max;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGap(min, max);

  @override
  void updateRenderObject(BuildContext context, _RenderGap renderObject) {
    renderObject
      ..min = min
      ..max = max;
  }
}

class _RenderGap extends RenderBox {
  _RenderGap(this._min, this._max);

  double _min;
  double _max;

  set min(double value) {
    if (value == _min) return;
    _min = value;
    markNeedsLayout();
  }

  set max(double value) {
    if (value == _max) return;
    _max = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) => _min;

  @override
  double computeMaxIntrinsicHeight(double width) => _min;

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
    Size(constraints.hasBoundedWidth ? constraints.maxWidth : 0, _max),
  );

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }
}
