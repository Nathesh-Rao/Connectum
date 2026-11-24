import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_filter_chips.dart';
import '../../../core/widgets/app_refresh.dart';
import '../../../core/widgets/app_state_view.dart';
import '../inbox_approvals_controller.dart';
import '../models/approval_pane.dart';
import 'approval_card.dart';

/// The Approvals pane: shown by the Inbox in place of its list. The filter
/// chips with their counts, then the cards, or the shared state view.
class ApprovalsPane extends StatelessWidget {
  const ApprovalsPane({super.key, required this.controller});

  final InboxApprovals controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      children: [
        _Filters(controller: c),
        Obx(
          () => c.hasError
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.xxs,
                    AppSpacing.page,
                    AppSpacing.xs,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      ApprovalPane.errorText,
                      style: AppText.caption.copyWith(color: AppColors.error),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: Obx(() {
            final state = c.viewState;
            return AnimatedSwitcher(
              duration: AppDurations.fast,
              switchInCurve: AppCurves.out,
              child: AppStateView(
                key: ValueKey(state),
                state: state,
                emptyTitle: state == AppViewState.noResults
                    ? ApprovalPane.noMatchText
                    : ApprovalPane.noneText,
                errorMessage: ApprovalPane.errorText,
                onRetry: c.reload,
                child: _List(controller: c),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final InboxApprovals controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      if (c.viewState == AppViewState.loading ||
          c.viewState == AppViewState.offline ||
          c.viewState == AppViewState.error) {
        return const SizedBox.shrink();
      }
      final counts = c.counts;
      final offered = c.offered;
      if (offered.length < 2) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        child: AppFilterChips(
          chips: [
            for (final f in offered)
              AppFilterChip(label: f.label, count: counts[f] ?? 0),
          ],
          selected: offered.indexOf(c.activeFilter),
          onSelected: (i) => c.select(offered[i]),
        ),
      );
    });
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller});

  final InboxApprovals controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppRefresh(
      onRefresh: c.reload,
      slivers: [
        Obx(() {
          final rows = c.rows;
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xs,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) => ApprovalSlot(
                key: ValueKey(rows[i].id),
                controller: c,
                request: rows[i],
              ),
            ),
          );
        }),
      ],
    );
  }
}
