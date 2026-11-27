import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';

/// A left drawer that slides the page aside: [child] moves right and shrinks
/// a little with a soft shadow, [drawer] stays under it. The state lives with
/// the owner ([isOpen]); a swipe or a tap reports through [onChanged].
///
/// The edge swipe starts just after the system back-gesture inset, so it does
/// not fight the back gesture, and only on a thin strip, so horizontal scroll
/// inside [child] is left alone. An open drawer closes on a tap on the page
/// or a swipe back.
class AppDrawerShell extends StatefulWidget {
  const AppDrawerShell({
    super.key,
    required this.isOpen,
    required this.onChanged,
    required this.drawer,
    required this.child,
  });

  final bool isOpen;
  final ValueChanged<bool> onChanged;
  final Widget drawer;
  final Widget child;

  @override
  State<AppDrawerShell> createState() => _AppDrawerShellState();
}

class _AppDrawerShellState extends State<AppDrawerShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: AppDurations.base,
    value: widget.isOpen ? 1 : 0,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _t,
    curve: AppCurves.out,
    reverseCurve: AppCurves.out,
  );
  double _width = AppSpacing.drawerMaxWidth;

  @override
  void didUpdateWidget(AppDrawerShell old) {
    super.didUpdateWidget(old);
    if (old.isOpen != widget.isOpen) _animateTo(widget.isOpen);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _animateTo(bool open) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.value = open ? 1 : 0;
    } else {
      _t.animateTo(open ? 1 : 0);
    }
  }

  void _drag(DragUpdateDetails d) {
    _t.value = (_t.value + d.delta.dx / _width).clamp(0.0, 1.0);
  }

  void _end(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dx;
    final open = v.abs() > 700 ? v > 0 : _t.value >= 0.5;
    _animateTo(open);
    if (open != widget.isOpen) widget.onChanged(open);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    _width = math.min(
      AppSpacing.drawerMaxWidth,
      size.width * AppSpacing.drawerWidthFactor,
    );
    final inset = MediaQuery.systemGestureInsetsOf(context).left;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _width,
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, child) => Offstage(
              offstage: _t.value == 0,
              child: ExcludeSemantics(excluding: !widget.isOpen, child: child),
            ),
            child: ColoredBox(color: AppColors.white, child: widget.drawer),
          ),
        ),
        AnimatedBuilder(
          animation: _curve,
          child: widget.child,
          builder: (context, child) {
            final t = _curve.value;
            final scale = 1 - (1 - AppDistances.drawerBodyScale) * t;
            return Transform.translate(
              offset: Offset(_width * t, 0),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  position: DecorationPosition.background,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg * t),
                    boxShadow: t == 0 ? null : AppShadows.drawerBody,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg * t),
                    child: child,
                  ),
                ),
              ),
            );
          },
        ),
        if (widget.isOpen)
          Positioned.fill(
            left: _width,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onChanged(false),
              onHorizontalDragUpdate: _drag,
              onHorizontalDragEnd: _end,
              child: const SizedBox.expand(),
            ),
          )
        else
          Positioned(
            left: inset,
            top: 0,
            bottom: 0,
            width: AppSpacing.drawerEdge,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: _drag,
              onHorizontalDragEnd: _end,
            ),
          ),
      ],
    );
  }
}
