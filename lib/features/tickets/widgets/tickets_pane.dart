import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_filter_chips.dart';
import '../../../core/widgets/app_filter_tabs.dart';
import '../../../core/widgets/app_refresh.dart';
import '../../../core/widgets/app_state_image.dart';
import '../../../core/widgets/app_state_view.dart';
import '../tickets_controller.dart';
import '../tickets_texts.dart';
import 'ticket_tile.dart';

/// The Tickets section: tabs "With me" (badge = total) and "Raised by me", a
/// filter by form when there is more than one, and the lists.
class TicketsPane extends StatelessWidget {
  const TicketsPane({super.key, required this.controller});

  final TicketsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyGeneric,
      AppStateImageKind.error,
      AppStateImageKind.offline,
    ]);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: Obx(
            () => AppFilterTabs(
              controller: c.tabController,
              tabs: [
                AppFilterTab(
                  label: TicketsTexts.tabWithMe,
                  count: c.withTotal.value,
                ),
                const AppFilterTab(label: TicketsTexts.tabRaised),
              ],
            ),
          ),
        ),
        Obx(() {
          final forms = c.forms;
          if (forms.length < 2) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.page,
              vertical: AppSpacing.xs,
            ),
            child: AppFilterChips(
              chips: [
                const AppFilterChip(label: TicketsTexts.filterAll),
                for (final f in forms) AppFilterChip(label: f.caption),
              ],
              selected: c.selectedIndex,
              onSelected: c.selectFilter,
            ),
          );
        }),
        Expanded(
          child: TabBarView(
            controller: c.tabController,
            children: [
              for (final as in TicketsController.tabs)
                _Pane(controller: c, as: as),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.controller, required this.as});

  final TicketsController controller;
  final String as;

  bool get _isWith => as == 'with';

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final list = c.lists[as]!;
    return Obx(() {
      final state = list.viewState.value;
      final items = c.visible(as);
      final isFiltered = c.selectedForm.value != null;
      final empty = AppStateView(
        state: state,
        emptyTitle: _isWith
            ? TicketsTexts.emptyWithTitle
            : TicketsTexts.emptyRaisedTitle,
        emptyMessage: isFiltered
            ? TicketsTexts.emptyFilteredMessage
            : _isWith
            ? TicketsTexts.emptyWithMessage
            : TicketsTexts.emptyRaisedMessage,
        errorMessage: TicketsTexts.errorMessage,
        onRetry: () => c.load(as, isQuiet: false),
        child: const SizedBox.shrink(),
      );
      if (state != AppViewState.content) {
        if (state != AppViewState.empty) return empty;
        return AppRefresh(
          onRefresh: () => c.load(as, isQuiet: false),
          slivers: [SliverFillRemaining(hasScrollBody: false, child: empty)],
        );
      }
      if (items.isEmpty) {
        return AppRefresh(
          onRefresh: () => c.load(as, isQuiet: false),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppStateView(
                state: AppViewState.empty,
                emptyTitle: _isWith
                    ? TicketsTexts.emptyWithTitle
                    : TicketsTexts.emptyRaisedTitle,
                emptyMessage: TicketsTexts.emptyFilteredMessage,
                child: const SizedBox.shrink(),
              ),
            ),
          ],
        );
      }
      return AppRefresh(
        onRefresh: () => c.load(as, isQuiet: false),
        slivers: [
          SliverList.separated(
            itemCount: items.length,
            separatorBuilder: (context, i) => const Divider(
              height: 1,
              color: AppColors.line,
              indent: AppSpacing.page,
              endIndent: AppSpacing.page,
            ),
            itemBuilder: (context, i) {
              final ticket = items[i];
              final tile = TicketTile(
                key: ValueKey(ticket.id),
                ticket: ticket,
                withName: c.tickets.isMe(ticket.withWhom)
                    ? TicketsTexts.you
                    : c.tickets.nameOf(ticket.withWhom),
                onTap: () => c.open(ticket),
              );
              return _SlideOut(
                key: ValueKey('row-${ticket.id}'),
                isLeaving: list.leaving.contains(ticket.id),
                child: tile,
              );
            },
          ),
          if (_isWith)
            SliverToBoxAdapter(
              child: Obx(
                () => list.hasMore.value
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: AppButton.secondary(
                          label: TicketsTexts.showMore,
                          isLoading: list.isLoadingMore.value,
                          onPressed: () => c.loadMore(as),
                        ),
                      )
                    : const SizedBox(height: AppSpacing.xl),
              ),
            ),
        ],
      );
    });
  }
}

/// A row that slides out to the side, fades and folds its height away when
/// it leaves the list (a row that stays is returned as it is).
class _SlideOut extends StatelessWidget {
  const _SlideOut({super.key, required this.isLeaving, required this.child});

  final bool isLeaving;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isLeaving) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1, end: 0),
      duration: AppDurations.slow,
      curve: AppCurves.out,
      builder: (context, v, _) => ClipRect(
        child: Align(
          heightFactor: v,
          alignment: Alignment.topCenter,
          child: Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset((1 - v) * 80, 0),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
