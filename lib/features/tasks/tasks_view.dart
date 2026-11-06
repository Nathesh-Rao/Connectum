import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_pill_bar.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_refresh.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../tickets/tickets_texts.dart';
import '../tickets/widgets/tickets_pane.dart';
import 'tasks_controller.dart';
import 'tasks_texts.dart';
import 'widgets/task_detail_sheet.dart';
import 'widgets/task_form_sheet.dart';
import 'widgets/task_tile.dart';

class TasksView extends GetView<TasksController> {
  const TasksView({super.key});

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
                  child: Text(TasksTexts.screenTitle, style: AppText.title),
                ),
                Obx(
                  () => c.selectedSection.value == 0
                      ? AppButton.icon(
                          icon: Icons.add,
                          semanticLabel: TasksTexts.newTask,
                          onPressed: () => TaskFormSheet.show(context, c),
                        )
                      : const SizedBox(width: AppSpacing.iconButton),
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
            child: Obx(
              () => AppPillBar(
                pills: const [
                  AppPill(
                    label: TicketsTexts.sectionTodos,
                    kind: AppPillKind.accent,
                  ),
                  AppPill(
                    label: TicketsTexts.sectionTickets,
                    kind: AppPillKind.sand,
                  ),
                ],
                selected: c.selectedSection.value,
                onSelected: (i) => c.selectedSection.value = i,
              ),
            ),
          ),
          Expanded(
            child: Obx(
              () => IndexedStack(
                index: c.selectedSection.value,
                children: [
                  _Todos(controller: c),
                  TicketsPane(controller: c.tickets),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Todos extends StatelessWidget {
  const _Todos({required this.controller});

  /// One per filter, in the order of [TasksController.filterLabels].
  static const _filterKinds = [
    AppPillKind.accent,
    AppPillKind.success,
    AppPillKind.calm,
    AppPillKind.neutral,
  ];

  final TasksController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page,
            vertical: AppSpacing.xs,
          ),
          child: Obx(
            () => AppPillBar(
              pills: const [
                AppPill(
                  label: TasksTexts.tabAssigned,
                  kind: AppPillKind.accent,
                ),
                AppPill(label: TasksTexts.tabCreated, kind: AppPillKind.sand),
              ],
              selected: c.selectedTab.value,
              onSelected: (i) => c.selectedTab.value = i,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: Obx(
            () => AppPillBar(
              pills: [
                for (var i = 0; i < TasksController.filterLabels.length; i++)
                  AppPill(
                    label: TasksController.filterLabels[i],
                    kind: _filterKinds[i],
                  ),
              ],
              selected: c.selectedFilter.value,
              onSelected: c.selectFilter,
            ),
          ),
        ),
        Expanded(
          child: Obx(
            () => IndexedStack(
              index: c.selectedTab.value,
              children: [
                for (final as in TasksController.tabs)
                  _Pane(controller: c, as: as),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.controller, required this.as});

  final TasksController controller;
  final String as;

  bool get _isAssigned => as == 'assigned';

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final list = c.lists[as]!;
    return Obx(() {
      final state = list.viewState.value;
      final items = list.items.toList();
      final isFiltered = c.selectedFilter.value != 0;
      final empty = AppStateView(
        state: state,
        emptyTitle: _isAssigned
            ? TasksTexts.emptyAssignedTitle
            : TasksTexts.emptyCreatedTitle,
        emptyMessage: isFiltered
            ? TasksTexts.emptyFilteredMessage
            : _isAssigned
            ? TasksTexts.emptyAssignedMessage
            : TasksTexts.emptyCreatedMessage,
        errorMessage: TasksTexts.errorMessage,
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
      return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) c.loadMore(as);
          return false;
        },
        child: AppRefresh(
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
                final task = items[i];
                return TaskTile(
                  key: ValueKey(task.id),
                  task: task,
                  user: c.me,
                  isAssignedTab: _isAssigned,
                  onTap: () => TaskDetailSheet.show(context, c, task.id),
                );
              },
            ),
            SliverToBoxAdapter(
              child: Obx(
                () => list.isLoadingMore.value
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: Center(child: AppSpinner()),
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
