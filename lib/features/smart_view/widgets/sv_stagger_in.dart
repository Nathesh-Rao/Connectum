import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';

/// Fades and lifts its child in, [index] steps after the first. With
/// animations off it is simply there.
class SvStaggerIn extends StatefulWidget {
  const SvStaggerIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<SvStaggerIn> createState() => _SvStaggerInState();
}

class _SvStaggerInState extends State<SvStaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  bool _isStarted = false;

  Duration get _delay => AppSv.ovStagger * widget.index;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: _delay + AppSv.ovEnter);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isStarted) return;
    _isStarted = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _anim.value = 1;
    } else {
      _anim.forward();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = (_delay + AppSv.ovEnter).inMilliseconds;
    final curve = CurvedAnimation(
      parent: _anim,
      curve: Interval(
        _delay.inMilliseconds / total,
        1,
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, AppSv.ovSlide * (1 - curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
