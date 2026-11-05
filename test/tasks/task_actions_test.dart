import 'package:connectum/data/models/task.dart';
import 'package:connectum/features/tasks/models/task_actions.dart';
import 'package:flutter_test/flutter_test.dart';

Task task({
  String status = Task.open,
  String creator = 'priya',
  String assignee = 'me',
}) => Task(id: 1, creator: creator, assignee: assignee, status: status);

void main() {
  test('the creator of an open task may edit, cancel and send, not start', () {
    final a = TaskActions.of(task(assignee: 'erin', creator: 'me'), 'me');
    expect(a.canEdit, isTrue);
    expect(a.canCancel, isTrue);
    expect(a.canSend, isTrue);
    expect(a.canReopen, isFalse);
    expect(a.canStart, isTrue);
    expect(a.canComplete, isTrue);
  });

  test('the assignee may only move the status', () {
    final a = TaskActions.of(task(), 'me');
    expect(a.canStart, isTrue);
    expect(a.canComplete, isTrue);
    expect(a.canEdit, isFalse);
    expect(a.canCancel, isFalse);
    expect(a.canSend, isFalse);
    expect(a.canReopen, isFalse);
  });

  test('in progress cannot be started again but can be completed', () {
    final a = TaskActions.of(task(status: Task.inProgress), 'me');
    expect(a.canStart, isFalse);
    expect(a.canComplete, isTrue);
  });

  test('a finished task: the creator reopens, nobody edits', () {
    for (final status in [Task.done, Task.cancelled]) {
      final creator = TaskActions.of(
        task(status: status, creator: 'me', assignee: 'erin'),
        'me',
      );
      expect(creator.canReopen, isTrue);
      expect(creator.canEdit, isFalse);
      expect(creator.canCancel, isFalse);
      expect(creator.canSend, isFalse);
      expect(creator.canStart, isFalse);
      expect(creator.canComplete, isFalse);
      final assignee = TaskActions.of(task(status: status), 'me');
      expect(assignee.hasAny, isFalse);
    }
  });

  test('someone with no part in the task may do nothing', () {
    expect(TaskActions.of(task(), 'stranger').hasAny, isFalse);
  });

  test('a task I gave myself: everything while active', () {
    final a = TaskActions.of(task(creator: 'me', assignee: 'me'), 'me');
    expect(a.canEdit && a.canCancel && a.canSend && a.canComplete, isTrue);
  });

  test('usernames compare without case', () {
    expect(TaskActions.of(task(creator: 'Priya'), 'priya').canEdit, isTrue);
  });
}
