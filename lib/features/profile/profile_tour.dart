import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/tour/tour.dart';

/// The first-run tour of the Profile screen: five steps (the picture and
/// details, your status, Security, Switch enterprise, Replay all tours). Rows below the
/// fold are scrolled into view as their step comes. The keys are put on the
/// screen's own widgets by the view.
class ProfileTour {
  ProfileTour({required this.service});

  final TourService service;

  final identityKey = GlobalKey(debugLabel: 'tour-profile-identity');
  final statusKey = GlobalKey(debugLabel: 'tour-profile-status');
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
      target: statusKey,
      icon: Icons.circle_outlined,
      title: TourTexts.prStatusTitle,
      body: TourTexts.prStatusBody,
      tone: AppTones.green,
      gesture: TourGesture.tap,
      canScroll: true,
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
