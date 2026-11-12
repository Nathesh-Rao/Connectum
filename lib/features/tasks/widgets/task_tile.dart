import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../data/models/task.dart';
import '../models/task_due_label.dart';
import '../tasks_texts.dart';

/// One task in a list: title, who it is from or for, the due date in words,
/// the priority and the status.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.user,
    required this.isAssignedTab,
    required this.onTap,
  });

  final Task task;
  final String user;
  final bool isAssignedTab;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isOverdue = task.isOverdueAt(now);
    final due = TaskDueLabel.of(task, now);
    final who = isAssignedTab
        ? '${TasksTexts.fromLabel} ${task.isCreatedBy(user) ? TasksTexts.me : task.creatorLabel}'
        : '${TasksTexts.forLabel} ${task.isAssignedTo(user) ? TasksTexts.me : task.assigneeLabel}';
    final dim = task.isFinished;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  task.isHigh ? Icons.flag : Icons.radio_button_unchecked,
                  size: 18,
                  color: task.isHigh ? AppColors.primaryBright : AppColors.muted,
                  semanticLabel: task.isHigh ? 'High priority' : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowTitle.copyWith(
                        color: dim ? AppColors.muted : AppColors.ink,
                        decoration: task.status == Task.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(who, style: AppText.rowCaption),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (due != null)
                          Text(
                            due,
                            style: AppText.readableStrong.copyWith(
                              color: isOverdue
                                  ? AppColors.error
                                  : AppColors.muted,
                            ),
                          ),
                        AppTag(
                          label: TasksTexts.statusLabel(task.status),
                          tone: task.status == Task.inProgress
                              ? AppTagTone.accent
                              : AppTagTone.neutral,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
