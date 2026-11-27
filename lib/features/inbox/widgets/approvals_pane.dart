import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../inbox_approvals_controller.dart';
import '../inbox_tour.dart';
import '../models/approval_pane.dart';
import 'approval_card.dart';
import 'approval_filter_bar.dart';

/// The Approvals pane: shown by the Inbox in place of its list. The filter
/// row, then the cards, or the shared state view.
class ApprovalsPane extends StatelessWidget {
  const ApprovalsPane({
    super.key,
    required this.controller,
    this.tour,
    this.isSample,
  });

  final InboxApprovals controller;

  /// The first-run tour: its keys, and its sample requests while
  /// [isSample] says they show (never with a request of the person's own).
  final InboxTour? tour;
  final bool Function()? isSample;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final demo = tour?.demo;
    if (demo != null) {
      return Obx(() {
        if (isSample?.call() ?? false) {
          return _SampleApprovals(controller: c, tour: tour!);
        }
        return _real(c);
      });
    }
    return _real(c);
  }

  Widget _real(InboxApprovals c) {
    return Column(
      children: [
        _Filters(controller: c, tour: tour),
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
                child: _List(controller: c, tour: tour),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// The tour's sample requests: the real filter row and the real cards, with a
/// "Sample" tag on each. The buttons answer nothing.
class _SampleApprovals extends StatelessWidget {
  const _SampleApprovals({required this.controller, required this.tour});

  final InboxApprovals controller;
  final InboxTour tour;

  @override
  Widget build(BuildContext context) {
    final demo = tour.demo;
    return Column(
      children: [
        ApprovalFilterBar(controller: controller),
        Expanded(
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xs,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            children: [
              for (final (i, a) in demo.approvals.indexed)
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
                        key: i == 0 ? tour.approvalKey : null,
                        child: ApprovalCard(
                          controller: controller,
                          request: a,
                          sample: demo,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller, this.tour});

  final InboxApprovals controller;
  final InboxTour? tour;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final state = c.viewState;
      if (state == AppViewState.loading ||
          state == AppViewState.offline ||
          state == AppViewState.error ||
          state == AppViewState.empty) {
        return const SizedBox.shrink();
      }
      return ApprovalFilterBar(controller: c);
    });
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller, this.tour});

  final InboxApprovals controller;
  final InboxTour? tour;

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
              itemBuilder: (context, i) => KeyedSubtree(
                key: i == 0 ? tour?.approvalKey : null,
                child: ApprovalSlot(
                  key: ValueKey(rows[i].id),
                  controller: c,
                  request: rows[i],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
