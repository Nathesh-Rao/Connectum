import 'package:connectum/data/models/task.dart';
import 'package:connectum/features/tasks/models/task_due_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a full task view parses', () {
    final t = Task.tryParse({
      'id': 7,
      'title': 'Send report',
      'description': 'Q4',
      'creator': 'priya',
      'assignee': 'me',
      'due': 1793477900047,
      'priority': 'high',
      'status': 'in_progress',
      'created': 10,
      'updated': 20,
      'doneTs': null,
      'overdue': false,
      'creatorName': 'Priya S',
      'assigneeName': 'Me',
    })!;
    expect(t.id, 7);
    expect(t.title, 'Send report');
    expect(t.due, 1793477900047);
    expect(t.priority, 'high');
    expect(t.status, Task.inProgress);
    expect(t.doneTs, isNull);
    expect(t.creatorLabel, 'Priya S');
  });

  test('missing fields fall back and do not throw', () {
    final t = Task.tryParse({'id': '9'})!;
    expect(t.id, 9);
    expect(t.title, '');
    expect(t.due, isNull);
    expect(t.priority, 'normal');
    expect(t.status, Task.open);
    expect(t.creatorLabel, '');
  });

  test('an unknown priority becomes normal; names fall back to usernames', () {
    final t = Task.tryParse({
      'id': 1,
      'priority': 'urgent',
      'creator': 'sam',
      'assignee': 'erin',
    })!;
    expect(t.priority, 'normal');
    expect(t.creatorLabel, 'sam');
    expect(t.assigneeLabel, 'erin');
  });

  test('no usable id means no task', () {
    expect(Task.tryParse({'title': 'x'}), isNull);
    expect(Task.tryParse('nope'), isNull);
    expect(Task.tryParse(null), isNull);
  });

  test('a page parses, skips rows without an id and reads hasMore', () {
    final page = TaskPage.parse({
      'tasks': [
        {'id': 1},
        {'title': 'no id'},
        {'id': 2},
      ],
      'total': 5,
      'hasMore': true,
    });
    expect(page.tasks.map((t) => t.id), [1, 2]);
    expect(page.total, 5);
    expect(page.hasMore, isTrue);
    final empty = TaskPage.parse({});
    expect(empty.tasks, isEmpty);
    expect(empty.hasMore, isFalse);
  });

  test('overdue is worked out from the due date, only while active', () {
    final now = DateTime(2026, 11, 5, 12);
    final past = now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
    expect(Task(id: 1, due: past).isOverdueAt(now), isTrue);
    expect(Task(id: 1, due: past, status: Task.done).isOverdueAt(now), isFalse);
    expect(const Task(id: 1).isOverdueAt(now), isFalse);
  });

  test('due text: today, tomorrow, overdue, a date', () {
    final now = DateTime(2026, 11, 5, 12);
    int at(DateTime d) => d.millisecondsSinceEpoch;
    String? label(DateTime d) => TaskDueLabel.of(Task(id: 1, due: at(d)), now);
    expect(label(DateTime(2026, 11, 5, 23, 59)), 'Due today');
    expect(label(DateTime(2026, 11, 6, 23, 59)), 'Due tomorrow');
    expect(label(DateTime(2026, 11, 3, 23, 59)), 'Overdue by 2 days');
    expect(label(DateTime(2026, 11, 4, 8)), 'Overdue by 1 day');
    expect(label(DateTime(2026, 11, 5, 8)), 'Overdue today');
    expect(label(DateTime(2026, 11, 20, 23, 59)), 'Due 20 Nov');
    expect(label(DateTime(2027, 1, 2, 23, 59)), 'Due 2 Jan 2027');
    expect(TaskDueLabel.of(const Task(id: 1), now), isNull);
  });
}
