import 'dart:async';

import 'package:flutter/widgets.dart';

import '../log/app_log.dart';
import '../log/safe.dart';
import 'tour_action.dart';
import 'tour_demo.dart';
import 'tour_step.dart';
import 'widgets/tour_pointer.dart';

/// Plays the actions of the steps of one tour and puts everything back.
/// [restore] is the one place that undoes the actions and the sample data:
/// the service calls it from its single `_end`, so finish, skip, back, app
/// pause, a route change and any error all end up here. Nothing here throws.
class TourRunner {
  TourRunner({this.demo, this.pointer, this.isReduced = false});

  static const _tag = 'tour_runner';

  final TourDemo? demo;
  final TourPointerHost? pointer;
  final bool isReduced;

  final _live = <TourAction>[];
  bool _hasDemo = false;
  bool _isEnded = false;

  bool get isEnded => _isEnded;

  /// The actions that are on right now, oldest first.
  List<TourAction> get live => List.unmodifiable(_live);

  /// Puts the sample data in. True when it did.
  bool seed() {
    final d = demo;
    if (d == null || _isEnded) return false;
    _hasDemo = true;
    return safeSync(_tag, d.seed, fallback: false) ?? false;
  }

  /// Goes from step [from] (null at the start) to [to]: undoes what [from]
  /// did unless [to] carries it on, then plays the actions of [to] one by
  /// one, each followed by its settle time.
  Future<void> enter(TourStep? from, TourStep to) async {
    if (_isEnded) return;
    final carried = <String>{
      for (final a in to.actions)
        if (a.carry != null) a.carry!,
    };
    final kept = <String>{};
    for (final a in _live.reversed.toList()) {
      final carry = a.carry;
      if (carry != null && carried.contains(carry)) {
        kept.add(carry);
        continue;
      }
      _live.remove(a);
      _undo(a);
    }
    for (final a in to.actions) {
      if (_isEnded) return;
      if (a.carry != null && kept.contains(a.carry)) continue;
      await _play(a, to);
    }
    if (!_isEnded) unawaited(pointer?.hide() ?? Future<void>.value());
  }

  Future<void> _play(TourAction a, TourStep step) async {
    final gesture = a.gesture;
    final host = pointer;
    if (gesture != null && host != null && !isReduced) {
      final rect = _rectOf(a.target ?? step.target);
      if (rect != null) {
        try {
          await host.play(rect, gesture, isReduced: isReduced);
        } catch (e, st) {
          AppLog.e(_tag, e, st);
        }
      }
    }
    if (_isEnded) return;
    // Listed before it runs, so an end in the middle still undoes it.
    _live.add(a);
    try {
      await a.run();
    } catch (e, st) {
      AppLog.e(_tag, e, st);
    }
    if (_isEnded) return;
    if (!isReduced) await Future<void>.delayed(a.settle);
    if (!_isEnded) await WidgetsBinding.instance.endOfFrame;
  }

  static Rect? _rectOf(GlobalKey key) {
    final context = key.currentContext;
    if (context == null || !context.mounted) return null;
    return safeSync<Rect?>(_tag, () {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return null;
      return box.localToGlobal(Offset.zero) & box.size;
    });
  }

  void _undo(TourAction a) {
    final undo = a.undo;
    if (undo != null) safeSync(_tag, undo);
  }

  /// Undoes every live action (newest first), takes the sample data out and
  /// removes the pointer. Safe to call twice.
  void restore() {
    if (_isEnded) return;
    _isEnded = true;
    try {
      for (final a in _live.reversed.toList()) {
        _undo(a);
      }
    } finally {
      _live.clear();
      try {
        final d = demo;
        if (_hasDemo && d != null) safeSync(_tag, d.restore);
      } finally {
        pointer?.dispose();
      }
    }
  }
}
