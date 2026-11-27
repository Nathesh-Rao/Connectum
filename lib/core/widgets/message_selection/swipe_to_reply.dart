import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';

/// The numbers of the swipe-to-reply gesture, in one place.
class SwipeReply {
  SwipeReply._();

  /// The one switch for the direction: true drags toward the end side (right
  /// in left-to-right, left in right-to-left); false toward the start side.
  static const bool isTowardEnd = true;

  /// 1 when the row moves right on screen, -1 when it moves left.
  static double screenSign(TextDirection direction) {
    final towardEnd = isTowardEnd ? 1.0 : -1.0;
    return direction == TextDirection.rtl ? -towardEnd : towardEnd;
  }

  /// The row never moves further than this.
  static const double maxOffset = 64;

  /// Past this the icon is full size, one haptic tick plays, and a release
  /// starts the reply.
  static const double threshold = 48;

  /// Below this much movement past the threshold a drag still feels direct.
  static const double resistance = 0.25;

  /// A fling this fast (px/s) toward the reply side counts once the row has
  /// moved [flingMinOffset].
  static const double flingVelocity = 700;
  static const double flingMinOffset = 24;

  /// The start edge belongs to the system back gesture; a drag that begins
  /// inside it is left alone.
  static const double edgeInset = 24;

  /// Horizontal movement must beat vertical movement by this factor, so a
  /// diagonal drag scrolls the list.
  static const double horizontalBias = 1.5;

  static const double iconSize = 32;
  static const double iconInset = 16;
  static const double iconGlyph = 18;

  /// The row's offset for [raw] finger travel: direct up to the threshold,
  /// then it gets harder, and stops at [maxOffset].
  static double offsetFor(double raw) {
    if (raw <= 0) return 0;
    if (raw <= threshold) return raw;
    return (threshold + (raw - threshold) * resistance).clamp(0, maxOffset);
  }
}

/// Wraps one message row: dragging it toward [SwipeReply.isTowardEnd] shows a
/// reply icon behind it and, past the threshold, calls [onReply] once on
/// release. Only the translated row and the icon rebuild while dragging.
///
/// A null [onReply] or a false [isEnabled] means the row does not move at all.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.onReply,
    required this.child,
    this.isEnabled = true,
    this.label = 'Reply',
  });

  final VoidCallback? onReply;
  final bool isEnabled;
  final String label;
  final Widget child;

  @override
  State<SwipeToReply> createState() => SwipeToReplyState();
}

class SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  final _offset = ValueNotifier<double>(0);
  late final AnimationController _back;

  @override
  void initState() {
    super.initState();
    _back = AnimationController.unbounded(vsync: this)
      ..addListener(() => _offset.value = _back.value < 0 ? 0 : _back.value);
  }

  double _raw = 0;
  bool _isReached = false;

  bool get _isActive => widget.isEnabled && widget.onReply != null;

  /// Slides the row to the reply threshold and holds it there, the way a
  /// finger would, without replying. Used by the first-run tour; [reset]
  /// puts it back.
  Future<void> peek({required bool isReduced}) async {
    if (!_isActive) return;
    _back.stop();
    if (isReduced) {
      _offset.value = SwipeReply.threshold;
      return;
    }
    try {
      await _back
          .animateTo(
            SwipeReply.threshold,
            duration: AppDurations.base,
            curve: AppCurves.out,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
  }

  /// Brings the row back to rest.
  void reset() {
    if (!mounted) return;
    _back.stop();
    _springBack(_offset.value, MediaQuery.disableAnimationsOf(context));
  }

  @override
  void dispose() {
    _back.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _onStart(DragStartDetails d) {
    _back.stop();
    _raw = _offset.value;
    _isReached = false;
  }

  void _onUpdate(DragUpdateDetails d, double sign) {
    _raw = (_raw + d.delta.dx * sign).clamp(0, double.infinity);
    final next = SwipeReply.offsetFor(_raw);
    if (!_isReached && next >= SwipeReply.threshold) {
      _isReached = true;
      HapticFeedback.lightImpact();
    } else if (_isReached && next < SwipeReply.threshold) {
      _isReached = false;
    }
    _offset.value = next;
  }

  void _onEnd(DragEndDetails d, double sign, bool isReduced) {
    final velocity = (d.primaryVelocity ?? 0) * sign;
    final offset = _offset.value;
    final isFling =
        velocity >= SwipeReply.flingVelocity &&
        offset >= SwipeReply.flingMinOffset;
    final isDone = offset >= SwipeReply.threshold || isFling;
    _raw = 0;
    _isReached = false;
    _springBack(offset, isReduced);
    if (isDone && _isActive) widget.onReply!();
  }

  void _onCancel(bool isReduced) {
    _raw = 0;
    _isReached = false;
    _springBack(_offset.value, isReduced);
  }

  void _springBack(double from, bool isReduced) {
    if (from <= 0) return;
    _back.value = from;
    if (isReduced) {
      _back.animateTo(0, duration: AppDurations.reduced, curve: Curves.linear);
    } else {
      _back.animateWith(SpringSimulation(AppCurves.pressSpring, from, 0, 0));
    }
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final isReduced = MediaQuery.disableAnimationsOf(context);
    final sign = SwipeReply.screenSign(direction);
    final width = MediaQuery.sizeOf(context).width;
    final moving = ValueListenableBuilder<double>(
      valueListenable: _offset,
      child: widget.child,
      builder: (context, value, child) =>
          Transform.translate(offset: Offset(value * sign, 0), child: child),
    );
    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        PositionedDirectional(
          start: SwipeReply.isTowardEnd ? SwipeReply.iconInset : null,
          end: SwipeReply.isTowardEnd ? null : SwipeReply.iconInset,
          top: 0,
          bottom: 0,
          child: Center(
            child: _ReplyIcon(offset: _offset, isReduced: isReduced),
          ),
        ),
        moving,
      ],
    );
    Widget result = RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _SwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<_SwipeRecognizer>(
              () => _SwipeRecognizer(debugOwner: this),
              (r) {
                r.isAllowedAt = (position) =>
                    _isActive && !_isInStartEdge(position.dx, width, direction);
                r.onStart = _onStart;
                r.onUpdate = (d) => _onUpdate(d, sign);
                r.onEnd = (d) => _onEnd(d, sign, isReduced);
                r.onCancel = () => _onCancel(isReduced);
              },
            ),
      },
      child: stack,
    );
    if (_isActive) {
      result = Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: widget.label): widget.onReply!,
        },
        child: result,
      );
    }
    return result;
  }

  static bool _isInStartEdge(double x, double width, TextDirection d) =>
      d == TextDirection.rtl
      ? x > width - SwipeReply.edgeInset
      : x < SwipeReply.edgeInset;
}

/// A horizontal drag that gives way: it takes a gesture only when it starts
/// away from the system back edge and the movement is clearly horizontal.
/// Horizontal scrollables inside the message sit deeper in the tree and are
/// asked first, so they win the arena when the finger is on them.
class _SwipeRecognizer extends HorizontalDragGestureRecognizer {
  _SwipeRecognizer({super.debugOwner});

  bool Function(Offset position) isAllowedAt = (_) => true;
  Offset? _first;
  Offset? _last;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      isAllowedAt(event.position) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _first = event.position;
    _last = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _last = event.position;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    final first = _first;
    final last = _last;
    if (first != null && last != null) {
      final d = last - first;
      if (d.dx.abs() < d.dy.abs() * SwipeReply.horizontalBias) return false;
    }
    return super.hasSufficientGlobalDistanceToAccept(
      pointerDeviceKind,
      deviceTouchSlop,
    );
  }
}

class _ReplyIcon extends StatelessWidget {
  const _ReplyIcon({required this.offset, required this.isReduced});

  final ValueListenable<double> offset;
  final bool isReduced;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ValueListenableBuilder<double>(
      valueListenable: offset,
      builder: (context, value, _) {
        final progress = (value / SwipeReply.threshold).clamp(0.0, 1.0);
        if (value <= 0) return const SizedBox.shrink();
        final child = Container(
          width: SwipeReply.iconSize,
          height: SwipeReply.iconSize,
          decoration: const BoxDecoration(
            color: AppColors.primaryTint,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.reply,
            size: SwipeReply.iconGlyph,
            color: AppColors.primary,
          ),
        );
        return Opacity(
          opacity: progress,
          child: isReduced
              ? child
              : Transform.scale(scale: progress, child: child),
        );
      },
    ),
  );
}
