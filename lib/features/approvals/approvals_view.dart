import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_filter_chips.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_refresh.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/widgets/app_tab_bar.dart';
import 'approvals_controller.dart';
import 'approvals_texts.dart';
import 'widgets/approval_detail_sheet.dart';
import 'widgets/approval_tile.dart';

class ApprovalsView extends GetView<ApprovalsController> {
  const ApprovalsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyGeneric,
      AppStateImageKind.error,
      AppStateImageKind.offline,
    ]);
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.xxs,
            ),
            child: Row(
              children: [
                AppButton.icon(
                  icon: Icons.arrow_back,
                  semanticLabel: 'Back',
                  onPressed: Get.back,
                ),
                const Expanded(
                  child: Text(ApprovalsTexts.screenTitle, style: AppText.title),
                ),
              ],
            ),
          ),
          const AppOfflineBar(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.page,
              vertical: AppSpacing.xs,
            ),
            child: AppTabBar(
              controller: c.tabController,
              labels: const [ApprovalsTexts.tabReview, ApprovalsTexts.tabSent],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Obx(
              () => AppFilterChips(
                chips: [
                  for (final label in ApprovalsController.filterLabels)
                    AppFilterChip(label: label),
                ],
                selected: c.selectedFilter.value,
                onSelected: c.selectFilter,
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: c.tabController,
              children: [
                _Pane(controller: c, index: 0),
                _Pane(controller: c, index: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.controller, required this.index});

  final ApprovalsController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final items = c.tab(index);
      var state = c.viewState.value;
      if (state == AppViewState.content && items.isEmpty) {
        state = AppViewState.empty;
      }
      final empty = AppStateView(
        state: state,
        emptyTitle: index == 0
            ? ApprovalsTexts.emptyReviewTitle
            : ApprovalsTexts.emptySentTitle,
        emptyMessage: !c.isPendingFilter
            ? ApprovalsTexts.emptyHistoryMessage
            : index == 0
            ? ApprovalsTexts.emptyReviewMessage
            : ApprovalsTexts.emptySentMessage,
        errorMessage: ApprovalsTexts.errorMessage,
        onRetry: () => c.load(isQuiet: false),
        child: const SizedBox.shrink(),
      );
      if (state != AppViewState.content) {
        if (state != AppViewState.empty) return empty;
        return AppRefresh(
          onRefresh: () => c.load(isQuiet: false),
          slivers: [SliverFillRemaining(hasScrollBody: false, child: empty)],
        );
      }
      return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) c.loadMore();
          return false;
        },
        child: AppRefresh(
          onRefresh: () => c.load(isQuiet: false),
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
                final r = items[i];
                return ApprovalTile(
                  key: ValueKey(r.id),
                  request: r,
                  onTap: () => ApprovalDetailSheet.show(context, c, r),
                );
              },
            ),
            SliverToBoxAdapter(
              child: Obx(
                () => c.isLoadingMore.value
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: Center(child: AppSpinner.medium()),
                      )
                    : const SizedBox(height: AppSpacing.xl),
              ),
            ),
          ],
        ),
      );
    });
  }
}
