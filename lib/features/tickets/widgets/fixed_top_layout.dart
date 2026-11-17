import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/widgets/app_refresh.dart';

/// A page whose top block stays fixed while a panel fills all the height
/// below it. When the top block leaves the panel less than [minPanelHeight],
/// the page becomes one scroll view (top block, then the panel at its own
/// height) instead of overflowing. In the normal case the page itself never
/// scrolls.
class FixedTopLayout extends StatefulWidget {
  const FixedTopLayout({
    super.key,
    required this.top,
    required this.fixedPanel,
    required this.inlinePanel,
    required this.onRefresh,
    this.minPanelHeight = 160,
  });

  final Widget top;

  /// The panel in the fixed layout: it gets the remaining height.
  final Widget fixedPanel;

  /// The panel in the scrolling fallback: as tall as it needs.
  final Widget inlinePanel;

  /// Pull to refresh of the fallback; the fixed panel brings its own.
  final Future<void> Function() onRefresh;
  final double minPanelHeight;

  @override
  State<FixedTopLayout> createState() => _FixedTopLayoutState();
}

class _FixedTopLayoutState extends State<FixedTopLayout> {
  final ValueNotifier<double> _topHeight = ValueNotifier(0);
  bool _isDisposed = false;

  void _report(double height) {
    if (_isDisposed) return;
    _topHeight.value = height;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _topHeight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => ValueListenableBuilder<double>(
      valueListenable: _topHeight,
      builder: (context, topHeight, _) {
        final isScrolling = topHeight > box.maxHeight - widget.minPanelHeight;
        final top = _HeightProbe(onHeight: _report, child: widget.top);
        if (isScrolling) {
          return AppRefresh(
            onRefresh: widget.onRefresh,
            slivers: [
              SliverToBoxAdapter(child: top),
              SliverToBoxAdapter(child: widget.inlinePanel),
            ],
          );
        }
        return CustomMultiChildLayout(
          delegate: _FixedTopDelegate(),
          children: [
            LayoutId(id: _Slot.top, child: top),
            LayoutId(
              id: _Slot.panel,
              child: LayoutBuilder(
                builder: (context, panel) =>
                    panel.maxHeight < widget.minPanelHeight
                    ? const SizedBox.shrink()
                    : widget.fixedPanel,
              ),
            ),
          ],
        );
      },
    ),
  );
}

enum _Slot { top, panel }

class _FixedTopDelegate extends MultiChildLayoutDelegate {
  @override
  Size getSize(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout(Size size) {
    final top = layoutChild(
      _Slot.top,
      BoxConstraints(minWidth: size.width, maxWidth: size.width),
    );
    positionChild(_Slot.top, Offset.zero);
    final rest = (size.height - top.height).clamp(0.0, double.infinity);
    layoutChild(_Slot.panel, BoxConstraints.tight(Size(size.width, rest)));
    positionChild(_Slot.panel, Offset(0, top.height));
  }

  @override
  bool shouldRelayout(_FixedTopDelegate old) => false;
}

/// Tells how tall its child came out, after the frame.
class _HeightProbe extends SingleChildRenderObjectWidget {
  const _HeightProbe({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightProbe(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightProbe renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderHeightProbe extends RenderProxyBox {
  _RenderHeightProbe(this.onHeight);

  ValueChanged<double> onHeight;
  double _last = -1;

  @override
  void performLayout() {
    super.performLayout();
    if (size.height == _last) return;
    _last = size.height;
    final height = size.height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
