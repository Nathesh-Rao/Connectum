import 'package:flutter/material.dart';

import '../../core/theme/app_tones.dart';
import '../../core/tour/tour_action.dart';
import '../../core/tour/tour_demo.dart';
import '../../core/tour/tour_gesture.dart';
import '../../core/tour/tour_id.dart';
import '../../core/tour/tour_service.dart';
import '../../core/tour/tour_step.dart';
import '../../core/tour/tour_texts.dart';
import 'inbox_tour_demo.dart';

/// What the tour asks of the screen. Each one only changes UI state of the
/// screen (an open card, a popup, the shown tab); none reads or writes data.
class InboxTourPorts {
  const InboxTourPorts({
    required this.seed,
    required this.restore,
    required this.expandFirst,
    required this.collapseFirst,
    required this.openFilter,
    required this.closeFilter,
    required this.showApprovals,
    required this.showRecords,
  });

  /// Decides what is sample and what is real; true when anything is sample.
  final bool Function() seed;
  final void Function() restore;
  final void Function() expandFirst;
  final void Function() collapseFirst;
  final void Function() openFilter;
  final void Function() closeFilter;
  final void Function() showApprovals;
  final void Function() showRecords;
}

/// The first-run tour of the Inbox tab, seven steps that run the screen
/// themselves: a record card, the same card opened, the Views chip, Search
/// and the filter popup (it opens for a moment), then the pointer swipes to
/// the Approvals tab, which really switches, where the filter button and its
/// chips and the request cards are shown. The tour goes back to Records when
/// it ends, however it ends. A person with no record or no request sees
/// sample cards; real ones are always used when they exist. The keys are put
/// on the screen's own widgets by the view.
class InboxTour {
  InboxTour({required this.service});

  final TourService service;
  final demo = InboxTourDemo();

  final tabsKey = GlobalKey(debugLabel: 'tour-inbox-tabs');
  final pagesKey = GlobalKey(debugLabel: 'tour-inbox-pages');
  final viewsKey = GlobalKey(debugLabel: 'tour-inbox-views');
  final buttonsKey = GlobalKey(debugLabel: 'tour-inbox-buttons');
  final cardKey = GlobalKey(debugLabel: 'tour-inbox-card');
  final approvalKey = GlobalKey(debugLabel: 'tour-inbox-approval-card');

  static const _approvals = 'approvals';

  /// What the Approvals steps keep on: the Approvals tab shown. Silent, so
  /// the pointer swipes only once.
  TourAction _held(InboxTourPorts p) => TourAction(
    kind: TourActionKind.switchTab,
    showsPointer: false,
    carry: _approvals,
    run: p.showApprovals,
    undo: p.showRecords,
  );

  List<TourStep> steps(
    InboxTourPorts p, {
    required bool isSample,
    int pendingApprovals = 0,
  }) => [
    TourStep(
      target: cardKey,
      icon: Icons.article_outlined,
      title: TourTexts.inboxCardsTitle,
      body: TourTexts.inboxCardsBody(isSample: isSample),
      tone: AppTones.green,
    ),
    TourStep(
      target: cardKey,
      icon: Icons.unfold_more,
      title: TourTexts.inboxExpandTitle,
      body: TourTexts.inboxExpandBody,
      tone: AppTones.teal,
      actions: [
        TourAction(
          kind: TourActionKind.expandCard,
          target: cardKey,
          run: p.expandFirst,
          undo: p.collapseFirst,
        ),
      ],
    ),
    TourStep(
      target: viewsKey,
      icon: Icons.visibility_outlined,
      title: TourTexts.inboxViewsTitle,
      body: TourTexts.inboxViewsBody,
      tone: AppTones.violet,
    ),
    TourStep(
      target: buttonsKey,
      icon: Icons.search_rounded,
      title: TourTexts.inboxSearchTitle,
      body: TourTexts.inboxSearchBody,
      tone: AppTones.blue,
      actions: [
        TourAction(
          kind: TourActionKind.openSheet,
          target: buttonsKey,
          run: p.openFilter,
          undo: p.closeFilter,
        ),
      ],
    ),
    TourStep(
      target: tabsKey,
      icon: Icons.swap_horiz,
      title: TourTexts.inboxTabsTitle,
      body: TourTexts.inboxTabsBody(pending: pendingApprovals),
      tone: AppTones.primary,
      actions: [
        TourAction(
          kind: TourActionKind.switchTab,
          target: pagesKey,
          gestureOverride: TourGesture.swipeLeft,
          carry: _approvals,
          run: p.showApprovals,
          undo: p.showRecords,
        ),
      ],
    ),
    TourStep(
      target: buttonsKey,
      icon: Icons.tune_rounded,
      title: TourTexts.inboxFilterBarTitle,
      body: TourTexts.inboxFilterBarBody,
      tone: AppTones.indigo,
      actions: [_held(p)],
    ),
    TourStep(
      target: approvalKey,
      icon: Icons.fact_check_outlined,
      title: TourTexts.inboxApprovalsTitle,
      body: TourTexts.inboxApprovalsBody(isSample: isSample),
      tone: AppTones.green,
      actions: [_held(p)],
    ),
  ];

  Future<TourStart> start(
    InboxTourPorts ports, {
    required bool isSample,
    int pendingApprovals = 0,
  }) async {
    final context = tabsKey.currentContext;
    if (context == null || !context.mounted) return TourStart.blocked;
    return service.start(
      TourId.inbox,
      steps(ports, isSample: isSample, pendingApprovals: pendingApprovals),
      context: context,
      after: TourId.chatList,
      demo: TourDemo(seed: ports.seed, restore: ports.restore),
    );
  }

  void cancel() {
    if (service.activeId == TourId.inbox) service.cancel();
  }
}
