import '../../../data/models/task.dart';

/// The due date of a task in words: "Due today", "Due tomorrow", "Overdue by
/// 2 days", "Due 12 Nov".
class TaskDueLabel {
  TaskDueLabel._();

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "12 Nov", with the year when it is not this year.
  static String date(int ts, DateTime now) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final text = '${d.day} ${_months[d.month - 1]}';
    return d.year == now.year ? text : '$text ${d.year}';
  }

  static int _days(int ts, DateTime now) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  /// Null when the task has no due date.
  static String? of(Task task, DateTime now) {
    final due = task.due;
    if (due == null) return null;
    final days = _days(due, now);
    if (task.isOverdueAt(now)) {
      if (days >= 0) return 'Overdue today';
      return 'Overdue by ${-days} ${days == -1 ? 'day' : 'days'}';
    }
    return switch (days) {
      0 => 'Due today',
      1 => 'Due tomorrow',
      _ => 'Due ${date(due, now)}',
    };
  }
}
