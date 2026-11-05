import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/models/task.dart';
import '../chats/models/chat_person.dart';
import 'models/task_due_label.dart';
import 'models/task_form_rules.dart';
import 'tasks_texts.dart';

/// The create / edit form of one task. Made by the Tasks controller for one
/// sheet; [dispose] when the sheet closes. [onSubmit] sends the fields and
/// returns true when the server accepted them.
class TaskFormController {
  TaskFormController({
    this.task,
    required this.onSubmit,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    final t = task;
    if (t != null) {
      title.text = t.title;
      description.text = t.description;
      priority.value = t.priority;
      if (t.due != null) {
        due.value = DateTime.fromMillisecondsSinceEpoch(t.due!);
        _showDue();
      }
    }
  }

  /// The task being edited; null for a new one.
  final Task? task;
  final Future<bool> Function(Map<String, dynamic> fields) onSubmit;
  final DateTime Function() _clock;

  final title = TextEditingController();
  final description = TextEditingController();
  final due = Rxn<DateTime>();
  final priority = 'normal'.obs;

  /// Null means "me" (the server's default).
  final assignee = Rxn<ChatPerson>();

  /// What the read-only due and assignee fields show.
  final dueField = TextEditingController();
  final assigneeField = TextEditingController(text: TasksTexts.me);

  final isSubmitting = false.obs;
  final titleError = RxnString();
  final descriptionError = RxnString();
  final dueError = RxnString();
  bool _hasTried = false;

  bool get isEdit => task != null;

  DateTime? get _oldDue => task?.due == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(task!.due!);

  /// The first day the picker offers: today, or the task's own earlier due
  /// date so the picker can still show it.
  DateTime get firstDay {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final old = _oldDue;
    return old != null && old.isBefore(today)
        ? DateTime(old.year, old.month, old.day)
        : today;
  }

  void onChanged() {
    if (_hasTried) _validate();
  }

  void setDue(DateTime? day) {
    due.value = day;
    _showDue();
    onChanged();
  }

  void _showDue() {
    final day = due.value;
    dueField.text = day == null
        ? ''
        : TaskDueLabel.date(day.millisecondsSinceEpoch, _clock());
  }

  void setAssignee(ChatPerson person) {
    assignee.value = person;
    assigneeField.text = person.name;
  }

  bool _validate() {
    titleError.value = TaskFormRules.titleError(title.text);
    descriptionError.value = TaskFormRules.descriptionError(description.text);
    dueError.value = TaskFormRules.dueError(
      due.value,
      _clock(),
      unchanged: _oldDue,
    );
    return titleError.value == null &&
        descriptionError.value == null &&
        dueError.value == null;
  }

  /// One send at a time: a second tap while one is in flight does nothing,
  /// so a create can never be sent twice.
  Future<bool> submit() async {
    if (isSubmitting.value) return false;
    _hasTried = true;
    if (!_validate()) return false;
    final old = task;
    final fields = old == null
        ? TaskFormRules.createFields(
            title: title.text,
            description: description.text,
            due: due.value,
            priority: priority.value,
            assignee: assignee.value?.username,
          )
        : TaskFormRules.changes(
            old,
            title: title.text,
            description: description.text,
            due: due.value,
            priority: priority.value,
          );
    if (old != null && fields.isEmpty) return true;
    isSubmitting.value = true;
    try {
      return await onSubmit(fields);
    } finally {
      isSubmitting.value = false;
    }
  }
}
