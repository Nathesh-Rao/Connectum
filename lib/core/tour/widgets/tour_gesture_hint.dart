import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import '../tour_gesture.dart';

/// A small looping picture of a gesture, drawn with plain widgets. With the
/// reduce-motion setting on it shows one still frame.
class TourGestureHint extends StatefulWidget {
  const TourGestureHint({
    super.key,
    required this.gesture,
    required this.tone,
    required this.isReduced,
  });

  static const double width = 72;
  static const double height = 36;

  final TourGesture gesture;
  final AppTone tone;
  final bool isReduced;

  @override
  State<TourGestureHint> createState() => _TourGestureHintState();
}

class _TourGestureHintState extends State<TourGestureHint>
    with SingleTickerProviderStateMixin {
  static const _dot = 14.0;
  static const _stillAt = 0.55;

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: AppDurations.tourHint,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TourGestureHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.isReduced) {
      _loop
        ..stop()
        ..value = _stillAt;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;
    return ExcludeSemantics(
      child: SizedBox(
        width: TourGestureHint.width,
        height: TourGestureHint.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tone.tint,
            borderRadius: const BorderRadius.all(
              Radius.circular(AppRadius.control),
            ),
          ),
          child: AnimatedBuilder(
            animation: _loop,
            builder: (context, _) => switch (widget.gesture) {
              TourGesture.tap => _press(_loop.value, isLong: false),
              TourGesture.longPress => _press(_loop.value, isLong: true),
              TourGesture.swipeLeft => _swipe(_loop.value, isLeft: true),
              TourGesture.swipeRight => _swipe(_loop.value, isLeft: false),
              TourGesture.typeHash => _hash(_loop.value),
            },
          ),
        ),
      ),
    );
  }

  Widget _circle(double size, {Color? fill, Color? line, double stroke = 2}) =>
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: line == null ? null : Border.all(color: line, width: stroke),
        ),
      );

  /// A finger dot that presses, with a ring spreading out; a long press holds
  /// first and fills a ring.
  Widget _press(double t, {required bool isLong}) {
    final tone = widget.tone;
    final pressAt = isLong ? 0.15 : 0.3;
    final releaseAt = isLong ? 0.7 : 0.45;
    final isDown = t >= pressAt && t < releaseAt;
    final spread = t < releaseAt
        ? 0.0
        : Curves.easeOut.transform(
            ((t - releaseAt) / (1 - releaseAt)).clamp(0, 1),
          );
    final hold = isLong
        ? ((t - pressAt) / (releaseAt - pressAt)).clamp(0.0, 1.0)
        : 0.0;
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (spread > 0)
            Opacity(
              opacity: 1 - spread,
              child: _circle(_dot + 20 * spread, line: tone.solid),
            ),
          if (isLong && isDown)
            SizedBox(
              width: _dot + 12,
              height: _dot + 12,
              child: CircularProgressIndicator(
                value: hold,
                strokeWidth: 2,
                color: tone.solid,
                backgroundColor: tone.tintStrong,
              ),
            ),
          Transform.scale(
            scale: isDown ? 0.8 : 1,
            child: _circle(_dot, fill: tone.solid),
          ),
        ],
      ),
    );
  }

  /// A dot that slides across the box and fades out at the end.
  Widget _swipe(double t, {required bool isLeft}) {
    final tone = widget.tone;
    final move = Curves.easeInOut.transform(((t - 0.1) / 0.6).clamp(0, 1));
    final from = isLeft ? 1.0 : -1.0;
    final dx = from * (1 - 2 * move) * (TourGestureHint.width / 2 - _dot);
    final opacity = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
    return Center(
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: _circle(_dot, fill: tone.solid),
        ),
      ),
    );
  }

  /// A "#" that types in, then a blinking caret.
  Widget _hash(double t) {
    final tone = widget.tone;
    final isTyped = t > 0.3;
    final isCaret = (t * 4).floor().isEven;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: isTyped ? 1 : 0,
            child: Text(
              '#',
              style: AppText.subtitle.copyWith(color: tone.strong),
            ),
          ),
          Opacity(
            opacity: isCaret ? 1 : 0,
            child: Container(width: 2, height: 16, color: tone.solid),
          ),
        ],
      ),
    );
  }
}
