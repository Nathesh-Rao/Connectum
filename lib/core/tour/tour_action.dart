import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/app_motion.dart';
import 'tour_gesture.dart';

/// What a step does on its own when it becomes active. The pointer plays the
/// matching gesture first (see [TourAction.gesture]), then [run] changes the
/// screen's UI state.
enum TourActionKind {
  openDrawer,
  closeDrawer,
  selectMessage,
  clearSelection,
  switchTab,
  expandCard,
  openSheet,
  closeSheet,
  swipeRow,
  longPressRow,
  tapTarget,
}

/// One scripted action of a step. [run] and [undo] only change UI state
/// (a drawer, a selection, a tab, a swipe offset); they never write data,
/// send anything or read anything. [undo] runs when the person leaves the
/// step, or when the tour ends for any reason.
class TourAction {
  const TourAction({
    required this.kind,
    required this.run,
    this.undo,
    this.target,
    this.carry,
    this.showsPointer = true,
    this.gestureOverride,
    this.settle = AppDurations.base,
  });

  final TourActionKind kind;
  final FutureOr<void> Function() run;
  final void Function()? undo;

  /// Where the pointer goes; null means the step's own target.
  final GlobalKey? target;

  /// Two actions of neighbouring steps with the same [carry] are one action:
  /// going from the first step to the second neither undoes nor repeats it.
  final String? carry;

  /// False plays no pointer (the action is silent).
  final bool showsPointer;

  /// A gesture other than the kind's own (the tab switch is a swipe).
  final TourGesture? gestureOverride;

  /// How long the screen needs to finish moving after [run].
  final Duration settle;

  /// The gesture the pointer plays before [run]; null for actions that only
  /// close or clear something.
  TourGesture? get gesture {
    if (!showsPointer) return null;
    final own = gestureOverride;
    if (own != null) return own;
    return switch (kind) {
      TourActionKind.openDrawer ||
      TourActionKind.switchTab ||
      TourActionKind.expandCard ||
      TourActionKind.openSheet ||
      TourActionKind.tapTarget => TourGesture.tap,
      TourActionKind.longPressRow ||
      TourActionKind.selectMessage => TourGesture.longPress,
      TourActionKind.swipeRow => TourGesture.swipeRight,
      TourActionKind.closeDrawer ||
      TourActionKind.closeSheet ||
      TourActionKind.clearSelection => null,
    };
  }
}
