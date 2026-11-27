import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/tour/tour.dart';
import 'smart_view_tour_demo.dart';

/// What the tour asks of the screen. Each one only changes UI state of the
/// screen (the drawer, which records are shown, an expanded card, the filter
/// sheet); none reads or writes data.
class SvTourPorts {
  const SvTourPorts({
    required this.seed,
    required this.restore,
    required this.openDrawer,
    required this.closeDrawer,
    required this.pick,
    required this.unpick,
    required this.expandFirst,
    required this.collapseFirst,
    required this.openFilter,
    required this.closeFilter,
  });

  /// Decides what is sample and what is real; true when anything is sample.
  final bool Function() seed;
  final void Function() restore;
  final void Function() openDrawer;
  final void Function() closeDrawer;

  /// Shows the records of the view (the sample ones when no real ones).
  final void Function() pick;
  final void Function() unpick;
  final void Function() expandFirst;
  final void Function() collapseFirst;
  final void Function() openFilter;
  final void Function() closeFilter;
}

/// The first-run tour of the Smart view tab, seven steps that run the screen
/// themselves: the drawer opens and lists the views, a view is picked and its
/// records show as cards, then the mode switch, Search, Filter and Sort (the
/// filter sheet opens for a moment), the Actions button and an expanded card.
/// A person with no view sees one sample view and sample records; real views
/// and records are always used when they exist. The keys are put on the
/// screen's own widgets by the view.
class SmartViewTour {
  SmartViewTour({required this.service});

  final TourService service;
  final demo = SvTourDemo();

  final menuKey = GlobalKey(debugLabel: 'tour-sv-menu');
  final drawerKey = GlobalKey(debugLabel: 'tour-sv-drawer');
  final rowKey = GlobalKey(debugLabel: 'tour-sv-row');
  final cardKey = GlobalKey(debugLabel: 'tour-sv-card');
  final modeKey = GlobalKey(debugLabel: 'tour-sv-mode');
  final searchKey = GlobalKey(debugLabel: 'tour-sv-search');
  final filterKey = GlobalKey(debugLabel: 'tour-sv-filter');
  final fabKey = GlobalKey(debugLabel: 'tour-sv-fab');

  static const _drawer = 'drawer';
  static const _picked = 'picked';
  static const _closed = 'closed';

  /// What every step after the pick keeps on: the records shown, the drawer
  /// closed. Silent, so only the first of them draws a pointer.
  List<TourAction> _held(SvTourPorts p) => [
    TourAction(
      kind: TourActionKind.tapTarget,
      showsPointer: false,
      carry: _picked,
      run: p.pick,
      undo: p.unpick,
    ),
    TourAction(
      kind: TourActionKind.closeDrawer,
      carry: _closed,
      run: p.closeDrawer,
      undo: p.openDrawer,
    ),
  ];

  /// [isDrawerOpen] is the state the tour found: the first step then lights
  /// the open drawer and does nothing to it, and the step that needs the
  /// cards closes it (undone by going back or ending). Whatever the entry
  /// state, the screen puts it back (see `SmartViewController`).
  List<TourStep> steps(
    SvTourPorts p, {
    required bool isSample,
    bool hasFiles = false,
    bool isDrawerOpen = false,
  }) => [
    TourStep(
      target: drawerKey,
      icon: Icons.menu,
      title: TourTexts.svViewsTitle,
      body: TourTexts.svViewsBody(isSample: isSample),
      tone: AppTones.violet,
      actions: [
        if (!isDrawerOpen)
          TourAction(
            kind: TourActionKind.openDrawer,
            target: menuKey,
            carry: _drawer,
            run: p.openDrawer,
            undo: p.closeDrawer,
          ),
      ],
    ),
    TourStep(
      target: cardKey,
      icon: Icons.view_agenda_outlined,
      title: TourTexts.svCardsTitle,
      body: TourTexts.svCardsBody(isSample: isSample, hasFiles: hasFiles),
      tone: AppTones.teal,
      actions: [
        if (!isDrawerOpen)
          TourAction(
            kind: TourActionKind.openDrawer,
            showsPointer: false,
            carry: _drawer,
            run: p.openDrawer,
            undo: p.closeDrawer,
          ),
        TourAction(
          kind: TourActionKind.tapTarget,
          target: rowKey,
          carry: _picked,
          run: p.pick,
          undo: p.unpick,
        ),
        TourAction(
          kind: TourActionKind.closeDrawer,
          carry: _closed,
          run: p.closeDrawer,
          undo: p.openDrawer,
        ),
      ],
    ),
    TourStep(
      target: modeKey,
      icon: Icons.view_agenda_outlined,
      title: TourTexts.svModeTitle,
      body: TourTexts.svModeBody,
      tone: AppTones.indigo,
      actions: _held(p),
    ),
    TourStep(
      target: searchKey,
      icon: Icons.search,
      title: TourTexts.svSearchTitle,
      body: TourTexts.svSearchBody,
      tone: AppTones.blue,
      actions: _held(p),
    ),
    TourStep(
      target: filterKey,
      icon: Icons.filter_list,
      title: TourTexts.svFilterTitle,
      body: TourTexts.svFilterBody,
      tone: AppTones.green,
      actions: [
        ..._held(p),
        TourAction(
          kind: TourActionKind.openSheet,
          target: filterKey,
          run: p.openFilter,
          undo: p.closeFilter,
        ),
      ],
    ),
    TourStep(
      target: fabKey,
      icon: Icons.grid_view_rounded,
      title: TourTexts.svActionsTitle,
      body: TourTexts.svActionsBody,
      tone: AppTones.primary,
      shape: TourShape.circle,
      side: TourSide.above,
      actions: _held(p),
    ),
    TourStep(
      target: cardKey,
      icon: Icons.unfold_more,
      title: TourTexts.svExpandTitle,
      body: TourTexts.svExpandBody,
      tone: AppTones.teal,
      actions: [
        ..._held(p),
        TourAction(
          kind: TourActionKind.expandCard,
          target: cardKey,
          run: p.expandFirst,
          undo: p.collapseFirst,
        ),
      ],
    ),
  ];

  /// Starts the tour. [ports] reach the screen; [isSample] and [hasFiles]
  /// only choose the words (the sample is decided when it is seeded).
  Future<TourStart> start(
    SvTourPorts ports, {
    required bool isSample,
    bool hasFiles = false,
    bool isDrawerOpen = false,
  }) async {
    final context = menuKey.currentContext;
    if (context == null || !context.mounted) return TourStart.blocked;
    return service.start(
      TourId.smartView,
      steps(
        ports,
        isSample: isSample,
        hasFiles: hasFiles,
        isDrawerOpen: isDrawerOpen,
      ),
      context: context,
      after: TourId.chatList,
      demo: TourDemo(seed: ports.seed, restore: ports.restore),
    );
  }

  bool get isRunning => service.activeId == TourId.smartView;

  void cancel() {
    if (service.activeId == TourId.smartView) service.cancel();
  }
}
