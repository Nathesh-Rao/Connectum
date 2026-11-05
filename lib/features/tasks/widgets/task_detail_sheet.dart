import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_detail_row.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../data/models/task.dart';
import '../models/task_due_label.dart';
import '../tasks_controller.dart';
import '../tasks_texts.dart';
import 'task_form_sheet.dart';
import 'task_people_sheet.dart';

/// One task in full, with only the buttons this person may use. The sheet
/// follows the list, so an event or an answer shows here at once; a task
/// that left the lists (not found) closes it.
class TaskDetailSheet extends StatelessWidget {
  const TaskDetailSheet({
    super.key,
    required this.controller,
    required this.taskId,
    required this.initial,
  });

  final TasksController controller;
  final int taskId;
  final Task initial;

  static Future<void> show(
    BuildContext context,
    TasksController controller,
    int taskId,
  ) {
    final task = controller.find(taskId);
    if (task == null) return Future.value();
    return AppBottomSheet.show<void>(
      context,
      title: TasksTexts.detailTitle,
      child: TaskDetailSheet(
        controller: controller,
        taskId: taskId,
        initial: task,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final task = c.find(taskId) ?? initial;
      final actions = c.actionsOf(task);
      final now = DateTime.now();
      final due = TaskDueLabel.of(task, now);
      final isOverdue = task.isOverdueAt(now);
      final busy = c.isBusy.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(task.title, style: AppText.subtitle),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: AppTag(
              label: TasksTexts.statusLabel(task.status),
              tone: task.status == Task.inProgress
                  ? AppTagTone.accent
                  : AppTagTone.neutral,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppDetailRow(
            caption: TasksTexts.description,
            value: task.description.isEmpty
                ? TasksTexts.noDescription
                : task.description,
          ),
          AppDetailRow(
            caption: TasksTexts.createdBy,
            value: task.isCreatedBy(c.me) ? TasksTexts.you : task.creatorLabel,
          ),
          AppDetailRow(
            caption: TasksTexts.assignedTo,
            value: task.isAssignedTo(c.me)
                ? TasksTexts.you
                : task.assigneeLabel,
          ),
          AppDetailRow(
            caption: TasksTexts.due,
            value: due == null
                ? TasksTexts.noDue
                : '$due · ${TaskDueLabel.date(task.due!, now)}',
            valueColor: isOverdue ? AppColors.error : AppColors.ink,
          ),
          AppDetailRow(
            caption: TasksTexts.priority,
            value: TasksTexts.priorityLabel(task.priority),
          ),
          if (actions.hasAny) ...[
            const SizedBox(height: AppSpacing.md),
            if (actions.canStart)
              _Gap(
                AppButton.primary(
                  label: TasksTexts.start,
                  isCentered: true,
                  isLoading: busy,
                  onPressed: busy ? null : () => c.start(task),
                ),
              ),
            if (actions.canComplete)
              _Gap(
                AppButton.primary(
                  label: TasksTexts.markDone,
                  isCentered: true,
                  isLoading: busy,
                  onPressed: busy ? null : () => c.complete(task),
                ),
              ),
            if (actions.canReopen)
              _Gap(
                AppButton.primary(
                  label: TasksTexts.reopen,
                  isCentered: true,
                  isLoading: busy,
                  onPressed: busy ? null : () => c.reopen(task),
                ),
              ),
            if (actions.canEdit)
              _Gap(
                AppButton.secondary(
                  label: TasksTexts.edit,
                  onPressed: busy
                      ? null
                      : () => TaskFormSheet.show(context, c, task: task),
                ),
              ),
            if (actions.canSend)
              _Gap(
                AppButton.secondary(
                  label: TasksTexts.sendToSomeone,
                  onPressed: busy
                      ? null
                      : () => TaskPeopleSheet.show(
                          context,
                          c,
                          title: TasksTexts.sendTitle,
                          onPicked: (p) => c.sendTo(task, p),
                        ),
                ),
              ),
            if (actions.canCancel)
              _Gap(
                AppButton.secondary(
                  label: TasksTexts.cancelTask,
                  isDanger: true,
                  onPressed: busy ? null : () => c.cancel(task),
                ),
              ),
          ],
        ],
      );
    });
  }
}

class _Gap extends StatelessWidget {
  const _Gap(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: child,
  );
}
