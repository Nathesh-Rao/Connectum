import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/tour/tour.dart';

/// The first-run tour of the notifications screen: four steps (the priority
/// filters, tap to open, swipe to dismiss, the More menu). With no
/// notification yet the two gesture steps point at the empty body and show
/// the hint. The keys are put on the screen's own widgets by the view.
class NotificationsTour {
  NotificationsTour({required this.service});

  final TourService service;

  final pillsKey = GlobalKey(debugLabel: 'tour-nt-pills');
  final bodyKey = GlobalKey(debugLabel: 'tour-nt-body');
  final tileKey = GlobalKey(debugLabel: 'tour-nt-tile');
  final moreKey = GlobalKey(debugLabel: 'tour-nt-more');

  List<TourStep> steps({required bool hasTile}) {
    final target = hasTile ? tileKey : bodyKey;
    return [
      TourStep(
        target: pillsKey,
        icon: Icons.filter_list,
        title: TourTexts.ntPillsTitle,
        body: TourTexts.ntPillsBody,
        tone: AppTones.primary,
      ),
      TourStep(
        target: target,
        icon: Icons.touch_app_outlined,
        title: TourTexts.ntTapTitle,
        body: hasTile ? TourTexts.ntTapBody : TourTexts.ntTapEmptyBody,
        tone: AppTones.teal,
        gesture: TourGesture.tap,
      ),
      TourStep(
        target: target,
        icon: Icons.swipe_left_alt,
        title: TourTexts.ntSwipeTitle,
        body: TourTexts.ntSwipeBody,
        tone: AppTones.violet,
        gesture: TourGesture.swipeLeft,
      ),
      TourStep(
        target: moreKey,
        icon: Icons.more_vert,
        title: TourTexts.ntMoreTitle,
        body: TourTexts.ntMoreBody,
        tone: AppTones.indigo,
        shape: TourShape.circle,
      ),
    ];
  }

  Future<TourStart> start() async {
    final context = pillsKey.currentContext;
    if (context == null || !context.mounted) return TourStart.failed;
    return service.start(
      TourId.notifications,
      steps(hasTile: TourService.isVisible(tileKey)),
      context: context,
      after: TourId.chatList,
    );
  }

  void cancel() {
    if (service.activeId == TourId.notifications) service.cancel();
  }
}
