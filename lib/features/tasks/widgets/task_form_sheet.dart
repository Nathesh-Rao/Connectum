import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/task.dart';
import '../models/task_form_rules.dart';
import '../task_form_controller.dart';
import '../tasks_controller.dart';
import '../tasks_texts.dart';
import 'task_people_sheet.dart';

/// Create (or, with [task], edit) a task: title, description, due date,
/// priority, and for a new task who it is for. One submit; the button waits
/// while a send is in flight, so a task is never created twice.
class TaskFormSheet extends StatelessWidget {
  const TaskFormSheet({
    super.key,
    required this.form,
    required this.controller,
  });

  final TaskFormController form;
  final TasksController controller;

  static Future<void> show(
    BuildContext context,
    TasksController controller, {
    Task? task,
  }) {
    final form = task == null
        ? controller.newForm()
        : controller.editForm(task);
    return AppBottomSheet.show<void>(
      context,
      title: task == null
          ? TasksTexts.formCreateTitle
          : TasksTexts.formEditTitle,
      child: TaskFormSheet(form: form, controller: controller),
      onDispose: form.dispose,
    );
  }

  Future<void> _pickDue(BuildContext context) async {
    final now = DateTime.now();
    final first = form.firstDay;
    final initial = form.due.value ?? now;
    final day = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: DateTime(now.year + 5),
      initialDate: initial.isBefore(first) ? first : initial,
    );
    if (day != null) form.setDue(day);
  }

  Future<void> _pickAssignee(BuildContext context) => TaskPeopleSheet.show(
    context,
    controller,
    title: TasksTexts.pickerTitle,
    onPicked: form.setAssignee,
  );

  @override
  Widget build(BuildContext context) {
    final f = form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(
          () => AppTextField(
            controller: f.title,
            label: TasksTexts.fieldTitle,
            hint: TasksTexts.fieldTitleHint,
            errorText: f.titleError.value,
            maxLength: TaskFormRules.titleMax,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            enabled: !f.isSubmitting.value,
            onChanged: (_) => f.onChanged(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => AppTextField(
            controller: f.description,
            label: TasksTexts.fieldDescription,
            hint: TasksTexts.fieldDescriptionHint,
            errorText: f.descriptionError.value,
            minLines: 3,
            maxLines: 6,
            maxLength: TaskFormRules.descriptionMax,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            enabled: !f.isSubmitting.value,
            onChanged: (_) => f.onChanged(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(() {
          final day = f.due.value;
          final canClear = day != null && !f.isEdit;
          return AppTextField(
            controller: f.dueField,
            label: TasksTexts.fieldDue,
            hint: TasksTexts.fieldDueHint,
            errorText: f.dueError.value,
            readOnly: true,
            enabled: !f.isSubmitting.value,
            onTap: () => _pickDue(context),
            leading: const Icon(
              Icons.event_outlined,
              size: 18,
              color: AppColors.muted,
            ),
            suffix: canClear
                ? AppButton.icon(
                    icon: Icons.close,
                    semanticLabel: TasksTexts.clearDue,
                    onPressed: () => f.setDue(null),
                  )
                : null,
          );
        }),
        const SizedBox(height: AppSpacing.md),
        const Text(TasksTexts.fieldPriority, style: AppText.fieldLabel),
        const SizedBox(height: AppSpacing.xs),
        Obx(
          () => _Segments(
            labels: [
              for (final p in Task.priorities) TasksTexts.priorityLabel(p),
            ],
            selected: Task.priorities.indexOf(f.priority.value),
            onSelected: (i) => f.priority.value = Task.priorities[i],
          ),
        ),
        if (!f.isEdit) ...[
          const SizedBox(height: AppSpacing.md),
          Obx(() {
            f.assignee.value;
            return AppTextField(
              controller: f.assigneeField,
              label: TasksTexts.fieldAssignee,
              readOnly: true,
              enabled: !f.isSubmitting.value,
              onTap: () => _pickAssignee(context),
              leading: const Icon(
                Icons.person_outline,
                size: 18,
                color: AppColors.muted,
              ),
              suffix: const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.rowChevron,
              ),
            );
          }),
        ],
        const SizedBox(height: AppSpacing.lg),
        Obx(
          () => AppButton.primary(
            label: f.isEdit ? TasksTexts.save : TasksTexts.create,
            isCentered: true,
            isLoading: f.isSubmitting.value,
            onPressed: f.isSubmitting.value
                ? null
                : () async {
                    final ok = await f.submit();
                    if (ok && context.mounted) Navigator.of(context).pop();
                  },
          ),
        ),
      ],
    );
  }
}

/// Three or so choices side by side; the chosen one is tinted.
class _Segments extends StatelessWidget {
  const _Segments({
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(i),
                  child: AnimatedContainer(
                    duration: AppDurations.fast,
                    curve: AppCurves.out,
                    height: AppSpacing.segmentHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected
                          ? AppColors.accentTint
                          : Colors.transparent,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppRadius.segment),
                      ),
                    ),
                    child: Text(
                      labels[i],
                      style: i == selected
                          ? AppText.segmentSelected
                          : AppText.segment,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
