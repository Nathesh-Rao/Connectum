import '../../../data/models/task.dart';
import '../tasks_texts.dart';

/// The limits `task.create` and `task.update` enforce, checked before sending
/// so the person is told at once. The server still has the last word.
class TaskFormRules {
  TaskFormRules._();

  static const titleMax = 120;
  static const descriptionMax = 2000;

  static String? titleError(String raw) {
    final title = raw.trim();
    if (title.isEmpty) return TasksTexts.titleRequired;
    if (title.length > titleMax) return TasksTexts.titleTooLong;
    return null;
  }

  static String? descriptionError(String raw) =>
      raw.trim().length > descriptionMax ? TasksTexts.descriptionTooLong : null;

  /// A due date is a day; it may be today or later. A date the task already
  /// has ([unchanged]) is not checked again, so an overdue task can be edited.
  static String? dueError(DateTime? day, DateTime now, {DateTime? unchanged}) {
    if (day == null) return null;
    if (unchanged != null && _sameDay(day, unchanged)) return null;
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(day.year, day.month, day.day).isBefore(today)
        ? TasksTexts.duePast
        : null;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// The end of the chosen day, so "today" is never in the past.
  static int dueOf(DateTime day) =>
      DateTime(day.year, day.month, day.day, 23, 59, 59).millisecondsSinceEpoch;

  static bool isValid(
    String title,
    String description,
    DateTime? due,
    DateTime now, {
    DateTime? unchanged,
  }) =>
      titleError(title) == null &&
      descriptionError(description) == null &&
      dueError(due, now, unchanged: unchanged) == null;

  /// The fields of `task.create`. The assignee is left out for "me" (the
  /// default).
  static Map<String, dynamic> createFields({
    required String title,
    required String description,
    required DateTime? due,
    required String priority,
    String? assignee,
  }) => {
    'title': title.trim(),
    if (description.trim().isNotEmpty) 'description': description.trim(),
    if (due != null) 'due': dueOf(due),
    'priority': priority,
    if (assignee != null && assignee.isNotEmpty) 'assignee': assignee,
  };

  /// Only what changed, for `task.update`; empty when nothing did.
  static Map<String, dynamic> changes(
    Task old, {
    required String title,
    required String description,
    required DateTime? due,
    required String priority,
  }) {
    final oldDue = old.due == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(old.due!);
    return {
      if (title.trim() != old.title) 'title': title.trim(),
      if (description.trim() != old.description.trim())
        'description': description.trim(),
      if (due != null && (oldDue == null || !_sameDay(due, oldDue)))
        'due': dueOf(due),
      if (priority != old.priority) 'priority': priority,
    };
  }
}
