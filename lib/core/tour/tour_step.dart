import 'package:flutter/widgets.dart';

import '../theme/app_tones.dart';
import 'tour_action.dart';
import 'tour_gesture.dart';

enum TourShape { roundedRect, circle }

/// Where the card goes. [auto] picks the side with more room when the tour
/// starts; a target that only appears after the step's actions (a bar) is
/// not there yet at that moment, so such a step says it.
enum TourSide { auto, above, below }

/// One stop of a tour. [title] and [body] come from `tour_texts.dart`.
class TourStep {
  const TourStep({
    required this.target,
    required this.icon,
    required this.title,
    required this.body,
    this.tone = AppTones.primary,
    this.shape = TourShape.roundedRect,
    this.gesture,
    this.isAllowed,
    this.canScroll = false,
    this.actions = const [],
    this.side = TourSide.auto,
  });

  final GlobalKey target;
  final IconData icon;
  final String title;
  final String body;
  final AppTone tone;
  final TourShape shape;
  final TourGesture? gesture;

  /// Null means allowed. A step the person's permissions do not allow is left
  /// out.
  final bool Function()? isAllowed;

  /// A target inside a scroll view may be off screen when the tour starts:
  /// the step is kept and the view is scrolled to it when its turn comes.
  final bool canScroll;

  /// Played when the step becomes active, before the spotlight moves to the
  /// target; undone when the person leaves the step or the tour ends.
  final List<TourAction> actions;
  final TourSide side;
}
