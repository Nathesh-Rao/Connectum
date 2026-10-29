import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_filter_chips.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_skeleton.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/widgets/app_text_field.dart';
import 'submissions_controller.dart';
import 'widgets/submission_tile.dart';

class SubmissionsView extends GetView<SubmissionsController> {
  const SubmissionsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyGeneric,
      AppStateImageKind.error,
      AppStateImageKind.noResults,
    ]);
    return AppScaffold(
      hasOuterBottomBar: true,
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              AppSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('My Submissions', style: AppText.heading),
            ),
          ),
          const AppOfflineBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xs,
              AppSpacing.page,
              AppSpacing.xs,
            ),
            child: AppTextField(
              controller: c.searchField,
              focusNode: c.searchFocus,
              hint: 'Search submissions',
              minHeight: AppSpacing.searchHeight,
              fillColor: AppColors.searchFill,
              borderColor: Colors.transparent,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadius.xs),
              ),
              leading: const Icon(
                Icons.search,
                size: 18,
                color: AppColors.muted,
              ),
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
          ),
          Obx(() {
            final forms = c.forms.toList();
            final statuses = c.statuses.toList();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: AnimatedSize(
                duration: AppDurations.fast,
                curve: AppCurves.out,
                alignment: Alignment.topCenter,
                child: Column(
                  children: [
                    if (forms.length > 1)
                      AppFilterChips(
                        chips: [
                          const AppFilterChip(label: 'All'),
                          for (final f in forms)
                            AppFilterChip(label: f.label, count: f.count),
                        ],
                        selected: c.selectedForm.value,
                        onSelected: (i) => c.selectedForm.value = i,
                      ),
                    if (statuses.isNotEmpty)
                      AppFilterChips(
                        chips: [
                          const AppFilterChip(label: 'Any status'),
                          for (final s in statuses) AppFilterChip(label: s),
                        ],
                        selected: c.selectedStatus.value,
                        onSelected: (i) => c.selectedStatus.value = i,
                      ),
                  ],
                ),
              ),
            );
          }),
          Expanded(child: _Body(controller: c)),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final SubmissionsController controller;

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
          emptyTitle: 'No submissions yet',
          emptyMessage: c.isOnline
              ? 'Forms you submit show up here.'
              : 'Connect to load your submissions.',
          errorMessage: 'We could not load your submissions.',
          onRetry: c.retry,
          loadingChild: const _SkeletonCards(),
          child: _List(controller: c),
        ),
      );
    });
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller});

  final SubmissionsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.background,
      onRefresh: c.refreshList,
      child: Obx(() {
        final rows = c.rows.toList();
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.sm,
            AppSpacing.page,
            AppSpacing.xl,
          ),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) => SubmissionTile(
            key: ValueKey(rows[i].card.id),
            row: rows[i],
            onTap: () => c.open(rows[i].card),
          ),
        );
      }),
    );
  }
}

class _SkeletonCards extends StatelessWidget {
  const _SkeletonCards();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonScope(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          children: [
            for (var i = 0; i < 3; i++) ...[
              const AppSkeleton(
                width: double.infinity,
                height: 150,
                radius: AppRadius.lg,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}
