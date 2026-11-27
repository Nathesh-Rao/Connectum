import 'package:flutter/material.dart';

import '../../core/theme/app_tones.dart';
import '../../core/tour/tour_gesture.dart';
import '../../core/tour/tour_id.dart';
import '../../core/tour/tour_service.dart';
import '../../core/tour/tour_step.dart';
import '../../core/tour/tour_texts.dart';

/// The first-run tour of the Profile screen: four steps (the picture and
/// details, Security, Switch enterprise, Replay all tours). Rows below the
/// fold are scrolled into view as their step comes. The keys are put on the
/// screen's own widgets by the view.
class ProfileTour {
  ProfileTour({required this.service});

  final TourService service;

  final identityKey = GlobalKey(debugLabel: 'tour-profile-identity');
  final securityKey = GlobalKey(debugLabel: 'tour-profile-security');
  final switchKey = GlobalKey(debugLabel: 'tour-profile-switch');
  final replayKey = GlobalKey(debugLabel: 'tour-profile-replay');

  List<TourStep> steps() => [
    TourStep(
      target: identityKey,
      icon: Icons.account_circle_outlined,
      title: TourTexts.prIdentityTitle,
      body: TourTexts.prIdentityBody,
      tone: AppTones.primary,
      gesture: TourGesture.tap,
    ),
    TourStep(
      target: securityKey,
      icon: Icons.shield_outlined,
      title: TourTexts.prSecurityTitle,
      body: TourTexts.prSecurityBody,
      tone: AppTones.teal,
      canScroll: true,
    ),
    TourStep(
      target: switchKey,
      icon: Icons.swap_horiz_rounded,
      title: TourTexts.prSwitchTitle,
      body: TourTexts.prSwitchBody,
      tone: AppTones.violet,
      canScroll: true,
    ),
    TourStep(
      target: replayKey,
      icon: Icons.explore_outlined,
      title: TourTexts.prReplayTitle,
      body: TourTexts.prReplayBody,
      tone: AppTones.green,
      canScroll: true,
    ),
  ];

  Future<TourStart> start() async {
    final context = identityKey.currentContext;
    if (context == null || !context.mounted) return TourStart.blocked;
    return service.start(
      TourId.profile,
      steps(),
      context: context,
      after: TourId.chatList,
    );
  }

  void cancel() {
    if (service.activeId == TourId.profile) service.cancel();
  }
}
