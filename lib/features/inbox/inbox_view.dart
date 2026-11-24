import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_filter_chips.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_refresh.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/widgets/app_text_field.dart';
import 'inbox_controller.dart';
import 'widgets/inbox_card.dart';

/// The Inbox tab: the person's records (Me) or the team's (My Team) as cards,
/// newest first. Room is kept in the header for the Filter, Views and
/// Approvals buttons of the next phases.
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
    return AppScaffold(
      hasOuterBottomBar: true,
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(InboxController.title, style: AppText.heading),
                ),
                Obx(
                  () => c.isRefreshing.value
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.xs),
                          child: AppSpinner(size: AppSpinnerSize.sm),
                        )
                      : const SizedBox.shrink(),
                ),
                AppButton.icon(
                  icon: Icons.refresh,
                  semanticLabel: 'Refresh',
                  onPressed: () => c.refreshList(),
                ),
              ],
            ),
          ),
          const AppOfflineBar(),
          _Search(controller: c),
          _Scope(controller: c),
          _Summary(controller: c),
          Expanded(child: _Body(controller: c)),
        ],
      ),
    );
  }
}

class _Search extends StatelessWidget {
  const _Search({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xs,
        AppSpacing.page,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: c.searchField,
            focusNode: c.searchFocus,
            hint: InboxController.searchHint,
            minHeight: AppSpacing.searchHeight,
            fillColor: AppColors.searchFill,
            borderColor: Colors.transparent,
            borderRadius: const BorderRadius.all(Radius.circular(AppRadius.xs)),
            leading: const Icon(Icons.search, size: 18, color: AppColors.muted),
            suffix: Obx(
              () => c.query.value.isEmpty
                  ? const SizedBox.shrink()
                  : AppButton.icon(
                      icon: Icons.close,
                      semanticLabel: 'Clear search',
                      onPressed: c.clearSearch,
                    ),
            ),
            textInputAction: TextInputAction.search,
            onChanged: c.onQueryChanged,
          ),
          Obx(
            () => c.isSearchFocused.value || c.query.value.isNotEmpty
                ? const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      InboxController.searchNote,
                      style: AppText.caption,
                    ),
                  )
                : const SizedBox.shrink(),
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
          chips: [for (final s in InboxScope.values) AppFilterChip(label: s.label)],
          selected: c.scope.value.index,
          onSelected: (i) => c.selectScope(InboxScope.values[i]),
        ),
      );
    });
  }
}

/// The total, and the line that says a read failed while the old list stays.
class _Summary extends StatelessWidget {
  const _Summary({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final total = c.totalLabel;
      final hasError = c.hasError.value && c.page.value != null;
      if (total.isEmpty && !hasError) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.xxs,
          AppSpacing.page,
          AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (total.isNotEmpty) Text(total, style: AppText.caption),
            if (hasError)
              Text(
                InboxController.errorText,
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
      final state = c.viewState.value;
      return AnimatedSwitcher(
        duration: AppDurations.fast,
        switchInCurve: AppCurves.out,
        child: AppStateView(
          key: ValueKey(state),
          state: state,
          emptyTitle: state == AppViewState.noResults
              ? InboxController.noMatchTitle
              : InboxController.emptyTitle,
          errorMessage: InboxController.errorText,
          onRetry: c.retry,
          child: _List(controller: c),
        ),
      );
    });
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
          final rows = c.rows;
          final isMore = c.isLoadingMore.value;
          return SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xxs,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            sliver: SliverList.builder(
              itemCount: rows.length + (isMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= rows.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Center(child: AppSpinner()),
                  );
                }
                final row = rows[i];
                return Padding(
                  key: ValueKey(row.id),
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: InboxCard(controller: c, row: row),
                );
              },
            ),
          );
        }),
      ],
    );
  }
}
