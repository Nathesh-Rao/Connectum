import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tour_step.dart';

/// Where a tour card goes. Pure: the free area is the screen minus the system
/// insets, the keyboard and the bottom navigation bar; the card sits above or
/// below the lit target, clamped inside the free area with [margin]. When
/// neither side has room (a tall target, a drawer or a sheet) it docks at the
/// bottom of the free area, still above the bar.
class TourPlacement {
  const TourPlacement._();

  static const double margin = 12;
  static const double gap = 8;

  /// [barTop] is the top edge of the bottom navigation bar, null when there
  /// is none on screen.
  static Rect freeArea({
    required Size screen,
    required EdgeInsets insets,
    double? barTop,
  }) {
    var bottom = screen.height - insets.bottom;
    if (barTop != null && barTop < bottom) bottom = barTop;
    final top = math.min(insets.top, bottom);
    return Rect.fromLTRB(insets.left, top, screen.width - insets.right, bottom);
  }

  /// The top-left of a card of [card] size for the lit area [spot].
  static Offset place({
    required Rect free,
    required Rect spot,
    required Size card,
    required TourSide side,
  }) {
    final x = (free.left + (free.width - card.width) / 2).clamp(
      free.left,
      math.max(free.left, free.right - card.width),
    );
    final minTop = free.top + margin;
    final maxTop = free.bottom - margin - card.height;
    final aboveTop = spot.top - gap - card.height;
    final belowTop = spot.bottom + gap;
    final fitsAbove = aboveTop >= minTop;
    final fitsBelow = belowTop <= maxTop;

    final double top;
    if (fitsAbove || fitsBelow) {
      final roomAbove = spot.top - free.top;
      final roomBelow = free.bottom - spot.bottom;
      final wantsAbove = switch (side) {
        TourSide.above => true,
        TourSide.below => false,
        TourSide.auto => roomAbove > roomBelow,
      };
      top = (wantsAbove ? fitsAbove : !fitsBelow) ? aboveTop : belowTop;
    } else {
      top = maxTop;
    }
    return Offset(x.toDouble(), math.max(minTop, top));
  }
}

/// Fills the overlay: an opaque layer that keeps every tap off the screen
/// underneath, and the card placed by [TourPlacement] once its size is known.
/// The target and the bar are measured after each frame (never during layout),
/// so a target that moves (a drawer sliding in) is followed.
class TourCardLayer extends StatefulWidget {
  const TourCardLayer({
    super.key,
    required this.target,
    required this.side,
    required this.spotPadding,
    required this.bottomBar,
    required this.child,
  });

  final GlobalKey target;
  final TourSide side;

  /// How far the lit area reaches past the target.
  final double spotPadding;

  /// Read at measure time; null when no bar is registered.
  final GlobalKey? Function() bottomBar;
  final Widget child;

  @override
  State<TourCardLayer> createState() => _TourCardLayerState();
}

class _TourCardLayerState extends State<TourCardLayer> {
  Rect? _spot;
  double? _barTop;
  bool _isMeasured = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  static Rect? _rectOf(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (box.size.isEmpty) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _measure() {
    if (!mounted) return;
    final spot = _rectOf(widget.target)?.inflate(widget.spotPadding);
    final barTop = _rectOf(widget.bottomBar())?.top;
    if (!_isMeasured || spot != _spot || barTop != _barTop) {
      setState(() {
        _isMeasured = true;
        _spot = spot;
        _barTop = barTop;
      });
    }
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final insets = EdgeInsets.fromLTRB(
      media.padding.left,
      media.padding.top,
      media.padding.right,
      math.max(media.padding.bottom, media.viewInsets.bottom),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            onVerticalDragStart: (_) {},
            onHorizontalDragStart: (_) {},
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: _isMeasured ? 1 : 0,
            child: CustomSingleChildLayout(
              delegate: _Delegate(
                spot: _spot,
                side: widget.side,
                insets: insets,
                barTop: _barTop,
              ),
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}

class _Delegate extends SingleChildLayoutDelegate {
  const _Delegate({
    required this.spot,
    required this.side,
    required this.insets,
    required this.barTop,
  });

  final Rect? spot;
  final TourSide side;
  final EdgeInsets insets;
  final double? barTop;

  Rect _free(Size size) =>
      TourPlacement.freeArea(screen: size, insets: insets, barTop: barTop);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final free = _free(constraints.biggest);
    return BoxConstraints(
      maxWidth: math.max(0.0, free.width - 2 * TourPlacement.margin),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final free = _free(size);
    final at = TourPlacement.place(
      free: free,
      spot: spot ?? Rect.fromLTWH(free.center.dx, free.center.dy, 0, 0),
      card: childSize,
      side: side,
    );
    return at;
  }

  @override
  bool shouldRelayout(_Delegate old) =>
      old.spot != spot ||
      old.side != side ||
      old.insets != insets ||
      old.barTop != barTop;
}
