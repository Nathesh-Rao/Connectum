import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'inbox_controller.dart';
import 'inbox_filter_controller.dart';
import 'widgets/approval_card.dart';
import 'widgets/approvals_pane.dart';
import 'widgets/inbox_chip_bar.dart';
import 'widgets/inbox_header.dart';
import 'widgets/inbox_tab_bar.dart';
import 'models/inbox_tab.dart';
import 'widgets/inbox_view_dialogs.dart';
import 'widgets/inbox_card.dart';
import 'widgets/inbox_filter_sheet.dart';

/// The Inbox tab: a header (search, filter, the open view), a tab bar and two
/// swipeable pages: the person's records (Me) or the team's (My Team) as
/// cards, newest first, and the Approvals pane.
class InboxView extends GetView<InboxController> {
  const InboxView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyGeneric,
      AppStateImageKind.error,
      AppStateImageKind.noResults,
      AppStateImageKind.offline,
    ]);
    return InboxPromptHost(
      controller: c,
      child: Obx(
        () => PopScope(
          canPop: !c.isBackBlocked && !c.isSearchOpen.value,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (c.isSearchOpen.value) {
              c.closeSearch();
            } else {
              _leave(context, c);
            }
          },
          child: _screen(context, c),
        ),
      ),
    );
  }

  /// Back or the back gesture with a change that is not saved: ask first,
  /// then leave.
  Future<void> _leave(BuildContext context, InboxController c) async {
    if (!await c.confirmLeave()) return;
    c.isLeaving.value = true;
    if (!context.mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      await SystemNavigator.pop();
    }
    c.isLeaving.value = false;
  }

  Widget _screen(BuildContext context, InboxController c) {
    return AppScaffold(
      hasOuterBottomBar: true,
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Stack(
        children: [
          Column(
            children: [
              InboxHeader(controller: c),
              const AppOfflineBar(),
              Expanded(child: InboxPages(controller: c)),
            ],
          ),
          _TourFilter(controller: c),
        ],
      ),
    );
  }
}

/// The tab bar and the swipeable pages. The [PageController] belongs to this
/// instance (the controller keeps only the tab index), so two Inbox views
/// alive at once never share one.
class InboxPages extends StatefulWidget {
  const InboxPages({super.key, required this.controller});

  final InboxController controller;

  @override
  State<InboxPages> createState() => _InboxPagesState();
}

class _InboxPagesState extends State<InboxPages> {
  late final PageController _pager = PageController(
    initialPage: widget.controller.tabIndex.value,
  );
  late final Worker _follow;

  @override
  void initState() {
    super.initState();
    _follow = ever(widget.controller.tabIndex, _goTo);
  }

  void _goTo(int i) {
    if (!_pager.hasClients || _pager.positions.length != 1) return;
    final pos = _pager.position;
    if (!pos.hasPixels || !pos.hasContentDimensions) return;
    if (_pager.page?.round() == i) return;
    fireAndLog(
      'inbox_view',
      () => _pager.animateToPage(
        i,
        duration: AppDurations.base,
        curve: AppCurves.out,
      ),
    );
  }

  @override
  void dispose() {
    _follow.dispose();
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Column(
      children: [
        KeyedSubtree(
          key: c.tour?.tabsKey,
          child: InboxTabBar(controller: c, pager: _pager),
        ),
        Expanded(
          key: c.tour?.pagesKey,
          child: PageView(
            controller: _pager,
            onPageChanged: c.onPageChanged,
            physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
            children: [
              for (final t in InboxTabs.all)
                _KeepAlive(
                  key: ValueKey('inbox-page-${t.id.name}'),
                  child: switch (t.id) {
                    InboxTab.records => _RecordsPage(controller: c),
                    InboxTab.approvals => ApprovalsPane(
                      controller: c.approvals,
                      tour: c.tour,
                      isSample: () => c.isTourApprovalsSample,
                    ),
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A tab's page stays built while the other one is shown, so its scroll
/// position and state stay.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({super.key, required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _RecordsPage extends StatelessWidget {
  const _RecordsPage({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      if (c.isFocused) return _Focus(controller: c);
      return Column(
        children: [
          _RecordChips(controller: c),
          _Scope(controller: c),
          _Summary(controller: c),
          Expanded(child: _Body(controller: c)),
        ],
      );
    });
  }
}

/// "View submission": a small strip ("Submission #N", Show all records) and
/// the one record's card, which behaves like every other card.
class _Focus extends StatelessWidget {
  const _Focus({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      key: const ValueKey('inbox-focus'),
      children: [
        Container(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.inboxStripHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          decoration: const BoxDecoration(
            color: AppColors.surfaceSubtle,
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Obx(
                  () => Text(
                    'Submission #${c.focusId.value ?? ''}',
                    style: AppText.readableStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              AppButton.text(
                label: 'Show all records',
                tone: AppTextButtonTone.accent,
                onPressed: c.showAllRecords,
              ),
            ],
          ),
        ),
        Expanded(
          child: Obx(() {
            final row = c.focusRow.value;
            if (row == null) {
              return const Center(child: AppSpinner());
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.lg,
              ),
              children: [InboxCard(controller: c, row: row)],
            );
          }),
        ),
      ],
    );
  }
}

/// The Records filters that are on, as removable chips under the tab bar.
class _RecordChips extends StatelessWidget {
  const _RecordChips({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => InboxChipBar(
        chips: [
          for (final chip in c.filterChips)
            InboxChipData(
              id: chip.id,
              label: chip.label,
              onRemove: () => c.removeFilterChip(chip),
            ),
        ],
      ),
    );
  }
}

class _Scope extends StatelessWidget {
  const _Scope({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      if (!c.isTeamShown) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        child: AppFilterChips(
          chips: [
            for (final s in InboxScope.values) AppFilterChip(label: s.label),
          ],
          selected: c.filter.value.wheres.isNotEmpty ? -1 : c.scope.value.index,
          onSelected: (i) => c.selectScope(InboxScope.values[i]),
        ),
      );
    });
  }
}

/// The line that says a read failed while the old list stays.
class _Summary extends StatelessWidget {
  const _Summary({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final hasError = c.hasError.value && c.page.value != null;
      final isStale = c.isApprovalsStale;
      if (!hasError && !isStale) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.xxs,
          AppSpacing.page,
          AppSpacing.xxs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasError)
              Text(
                InboxController.errorText,
                style: AppText.caption.copyWith(color: AppColors.error),
              ),
            if (isStale)
              Text(
                InboxController.approvalsErrorText,
                style: AppText.caption.copyWith(color: AppColors.error),
              ),
          ],
        ),
      );
    });
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      if (c.isTourRecordsSample) return _SampleList(controller: c);
      final state = c.viewState.value;
      return KeyedSubtree(
        child: AnimatedSwitcher(
          duration: AppDurations.fast,
          switchInCurve: AppCurves.out,
          child: KeyedSubtree(
            key: ValueKey(state),
            child: AppStateView(
              state: state,
              emptyTitle: state == AppViewState.noResults
                  ? InboxController.noMatchTitle
                  : c.emptyText,
              errorMessage: InboxController.errorText,
              onRetry: c.retry,
              child: _List(controller: c),
            ),
          ),
        ),
      );
    });
  }
}

/// The sample cards of the tour, drawn by the real [InboxCard] in the place
/// of the empty Records list. Each carries a "Sample" tag.
class _SampleList extends StatelessWidget {
  const _SampleList({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final demo = c.tour?.demo;
    if (demo == null) return const SizedBox.shrink();
    return ListView(
      key: const ValueKey('inbox-tour-sample'),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xxs,
        AppSpacing.page,
        AppSpacing.lg,
      ),
      children: [
        for (final (i, row) in demo.rows.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: AppTag(
                    label: TourTexts.sampleTag,
                    tone: AppTagTone.accent,
                  ),
                ),
                KeyedSubtree(
                  key: i == 0 ? c.tour?.cardKey : null,
                  child: InboxCard(controller: c, row: row, sample: demo),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The Records filter popup the tour shows for a moment, drawn under the
/// header buttons (a route would end the tour). It is the real panel on a
/// sample controller: nothing is read for it and nothing it does is kept.
class _TourFilter extends StatefulWidget {
  const _TourFilter({required this.controller});

  final InboxController controller;

  @override
  State<_TourFilter> createState() => _TourFilterState();
}

class _TourFilterState extends State<_TourFilter> {
  InboxFilterController? _panel;
  Worker? _watch;

  @override
  void initState() {
    super.initState();
    final demo = widget.controller.tour?.demo;
    if (demo != null) {
      _watch = ever(demo.isFilterOpen, (_) {
        if (!demo.isFilterOpen.value) _drop();
        if (mounted) setState(() {});
      });
    }
  }

  void _drop() {
    _panel?.onClose();
    _panel = null;
  }

  @override
  void dispose() {
    _watch?.dispose();
    _drop();
    super.dispose();
  }

  double _top() {
    final buttons = widget.controller.tour?.buttonsKey.currentContext;
    final stack = context.findAncestorRenderObjectOfType<RenderStack>();
    final box = buttons?.findRenderObject();
    if (stack == null || box is! RenderBox || !box.attached) return 0;
    return box.localToGlobal(Offset(0, box.size.height), ancestor: stack).dy;
  }

  @override
  Widget build(BuildContext context) {
    final demo = widget.controller.tour?.demo;
    if (demo == null || !demo.isFilterOpen.value) {
      return const SizedBox.shrink();
    }
    final panel = _panel ??= widget.controller.newSampleFilterPanel();
    return Positioned.fill(
      top: _top(),
      child: IgnorePointer(
        child: Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(color: AppColors.sheetBackdrop),
            ),
            InboxFilterPopupFrame(child: InboxFilterPanel(panel: panel)),
          ],
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppRefresh(
      controller: c.scroll,
      onRefresh: c.refreshList,
      slivers: [
        Obx(() {
          final items = c.listItems;
          final firstRow = items.indexWhere((e) => e.row != null);
          final isMore = c.isLoadingMore.value;
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xxs,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            sliver: SliverList.builder(
              itemCount: items.length + (isMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Center(child: AppSpinner()),
                  );
                }
                final heading = items[i].heading;
                if (heading != null) {
                  return Semantics(
                    header: true,
                    child: Padding(
                      key: ValueKey('day-$heading'),
                      padding: const EdgeInsets.only(
                        top: AppSpacing.xs,
                        bottom: AppSpacing.xs,
                      ),
                      child: Text(heading, style: AppText.fieldLabel),
                    ),
                  );
                }
                final row = items[i].row;
                if (row == null) return const SizedBox.shrink();
                return Padding(
                  key: ValueKey(row.id),
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: KeyedSubtree(
                    key: i == firstRow ? c.tour?.cardKey : null,
                    child: InboxCard(controller: c, row: row),
                  ),
                );
              },
            ),
          );
        }),
        Obx(() => _approvalsSliver(c)),
      ],
    );
  }

  /// The approvals under the records (or alone): their cards, and their own
  /// loading or error line; a failed read never blocks the records above.
  Widget _approvalsSliver(InboxController c) {
    if (!c.hasApprovalsPart) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final cards = c.approvalCards;
    final isLoading = c.isApprovalsLoading;
    final isFailed = c.isApprovalsFailed;
    final hasHeading = cards.isNotEmpty && c.rows.isNotEmpty;
    final count =
        (hasHeading ? 1 : 0) + cards.length + (isLoading || isFailed ? 1 : 0);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.lg,
      ),
      sliver: SliverList.builder(
        itemCount: count,
        itemBuilder: (context, i) {
          if (hasHeading && i == 0) {
            return Semantics(
              header: true,
              child: const Padding(
                padding: EdgeInsets.only(
                  top: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                ),
                child: Text(
                  InboxController.approvalsHeading,
                  style: AppText.fieldLabel,
                ),
              ),
            );
          }
          final at = i - (hasHeading ? 1 : 0);
          if (at >= cards.length) {
            return isLoading
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Center(child: AppSpinner()),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          InboxController.approvalsErrorText,
                          style: AppText.caption.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                        AppButton.text(
                          label: 'Retry',
                          tone: AppTextButtonTone.accent,
                          onPressed: () => c.approvals.reload(),
                        ),
                      ],
                    ),
                  );
          }
          final a = cards[at];
          return ApprovalSlot(
            key: ValueKey('approval-${a.id}'),
            controller: c.approvals,
            request: a,
            isLeavingNow: () => c.isApprovalLeaving(a),
          );
        },
      ),
    );
  }
}
