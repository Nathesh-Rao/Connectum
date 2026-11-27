import 'dart:async';

import 'package:flutter/material.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/theme/theme.dart';
import '../tour_gesture.dart';

/// Drives a [TourPointer]: moves it to a target and plays one gesture.
class TourPointerController extends ChangeNotifier {
  _TourPointerState? _state;

  /// True from the first [play] until [hide].
  bool get isShown => _state?.isShown ?? false;

  /// How many gestures were played (none with reduce-motion on).
  int plays = 0;

  /// The gesture of the last [play].
  TourGesture? lastGesture;

  /// Moves to [target] (global coordinates) and plays [gesture]. With
  /// [isReduced] nothing is drawn: it returns at once.
  Future<void> play(
    Rect target,
    TourGesture gesture, {
    required bool isReduced,
  }) async {
    if (isReduced) return;
    final state = _state;
    if (state == null) return;
    plays++;
    lastGesture = gesture;
    await state.play(target, gesture);
  }

  Future<void> hide() async => _state?.hide();
}

/// A soft circle that stands for a finger: it glides to a target, then taps
/// (ripple), long-presses (growing ring) or swipes (drag trail). It never
/// takes a touch, so Next and Skip stay usable under it.
class TourPointer extends StatefulWidget {
  const TourPointer({super.key, required this.controller});

  static const double size = 44;
  static const double ring = 76;
  static const double swipeReach = 140;
  static const double _fillAlpha = 0.28;
  static const double _edgeAlpha = 0.7;
  static const double _trailHeight = 6;

  final TourPointerController controller;

  @override
  State<TourPointer> createState() => _TourPointerState();
}

class _TourPointerState extends State<TourPointer>
    with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this);
  late final AnimationController _act = AnimationController(vsync: this);
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: AppDurations.tourFade,
  );

  Offset? _at;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  Offset? _trailFrom;
  TourGesture? _gesture;

  bool get isShown => _at != null && _fade.value > 0;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _move.addListener(_onMove);
    _act.addListener(() => setState(() {}));
    _fade.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (widget.controller._state == this) widget.controller._state = null;
    _move.dispose();
    _act.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _onMove() {
    final t = AppCurves.inOut.transform(_move.value);
    setState(() => _at = Offset.lerp(_from, _to, t));
  }

  Offset _local(Offset global) {
    final box = context.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
  }

  Future<void> play(Rect target, TourGesture gesture) async {
    final rect = _local(target.topLeft) & target.size;
    final isSwipe =
        gesture == TourGesture.swipeRight || gesture == TourGesture.swipeLeft;
    final start = isSwipe
        ? Offset(rect.left + rect.width * 0.25, rect.center.dy)
        : rect.center;
    _gesture = gesture;
    _trailFrom = null;
    _act.value = 0;
    final from =
        _at ?? start + const Offset(TourPointer.ring, TourPointer.ring);
    _from = from;
    _to = start;
    unawaited(_fade.forward());
    _move.duration = AppDurations.tourPointerMove;
    if (!await _guard(_move.forward(from: 0))) return;
    switch (gesture) {
      case TourGesture.tap:
        _act.duration = AppDurations.tourTap;
        await _guard(_act.forward(from: 0));
      case TourGesture.longPress:
        _act.duration = AppDurations.tourHold;
        await _guard(_act.forward(from: 0));
      case TourGesture.swipeRight || TourGesture.swipeLeft:
        final sign = gesture == TourGesture.swipeRight ? 1.0 : -1.0;
        final reach = (rect.width * 0.5).clamp(0.0, TourPointer.swipeReach);
        _trailFrom = start;
        _from = start;
        _to = start + Offset(sign * reach, 0);
        _move.duration = AppDurations.tourSwipe;
        await _guard(_move.forward(from: 0));
      case TourGesture.typeHash:
        break;
    }
  }

  Future<void> hide() async {
    if (!mounted) return;
    _trailFrom = null;
    _gesture = null;
    await _guard(_fade.reverse());
  }

  /// A stopped controller (the tour ended) throws on `orCancel`; this turns
  /// that into a plain false: the caller stops.
  Future<bool> _guard(TickerFuture f) async {
    try {
      await f.orCancel;
    } on TickerCanceled {
      return false;
    }
    return mounted;
  }

  @override
  Widget build(BuildContext context) {
    final at = _at;
    if (at == null) return const SizedBox.shrink();
    final gesture = _gesture;
    final t = _act.value;
    final children = <Widget>[];
    final trailFrom = _trailFrom;
    if (trailFrom != null) {
      final left = at.dx < trailFrom.dx ? at.dx : trailFrom.dx;
      children.add(
        Positioned(
          left: left,
          top: trailFrom.dy - TourPointer._trailHeight / 2,
          width: (at.dx - trailFrom.dx).abs(),
          height: TourPointer._trailHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(
                alpha: TourPointer._fillAlpha,
              ),
              borderRadius: BorderRadius.circular(TourPointer._trailHeight),
            ),
          ),
        ),
      );
    }
    if (gesture == TourGesture.tap && t > 0) {
      children.add(_ring(at, TourPointer.size + TourPointer.ring * t, 1 - t));
    }
    if (gesture == TourGesture.longPress && t > 0) {
      children.add(_ring(at, TourPointer.size + TourPointer.ring * t, 0.9));
    }
    final isPressed = gesture != null && t > 0 && t < 1;
    final size = TourPointer.size * (isPressed ? 0.86 : 1);
    children.add(
      Positioned(
        left: at.dx - size / 2,
        top: at.dy - size / 2,
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withValues(alpha: TourPointer._fillAlpha),
            border: Border.all(
              color: AppColors.primary.withValues(
                alpha: TourPointer._edgeAlpha,
              ),
              width: 2,
            ),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Opacity(
          opacity: _fade.value,
          child: Stack(clipBehavior: Clip.none, children: children),
        ),
      ),
    );
  }

  Widget _ring(Offset at, double size, double opacity) => Positioned(
    left: at.dx - size / 2,
    top: at.dy - size / 2,
    width: size,
    height: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primary.withValues(
            alpha: (opacity * TourPointer._edgeAlpha).clamp(0.0, 1.0),
          ),
          width: 3,
        ),
      ),
    ),
  );
}

/// Puts one [TourPointer] over the screen for the length of a tour. The entry
/// is created when the first gesture plays, so it sits above the tour's own
/// overlay.
class TourPointerHost {
  TourPointerHost(this._context);

  static const _tag = 'tour_pointer';

  final BuildContext _context;
  final controller = TourPointerController();
  OverlayEntry? _entry;

  OverlayEntry _newEntry() => OverlayEntry(
    builder: (_) => Positioned.fill(child: TourPointer(controller: controller)),
  );

  /// Shows the pointer overlay if it is not there yet.
  void ensure() {
    if (_entry != null || !_context.mounted) return;
    final overlay = Overlay.maybeOf(_context);
    if (overlay == null) return;
    _entry = _newEntry();
    overlay.insert(_entry!);
  }

  /// Brings the pointer above overlays added since (the tour's own).
  void raise() {
    final old = _entry;
    if (old == null || !_context.mounted) return;
    final overlay = Overlay.maybeOf(_context);
    if (overlay == null) return;
    safeSync(_tag, old.remove);
    _entry = _newEntry();
    overlay.insert(_entry!);
  }

  Future<void> play(
    Rect target,
    TourGesture gesture, {
    required bool isReduced,
  }) async {
    if (isReduced) return;
    ensure();
    await WidgetsBinding.instance.endOfFrame;
    await controller.play(target, gesture, isReduced: isReduced);
  }

  Future<void> hide() => controller.hide();

  void dispose() {
    final entry = _entry;
    _entry = null;
    if (entry != null) safeSync(_tag, entry.remove);
  }
}
