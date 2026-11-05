import 'package:connectum/data/models/task.dart';
import 'package:connectum/features/tasks/models/task_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

Task t(
  int id, {
  String creator = 'priya',
  String assignee = 'me',
  String status = Task.open,
  int? due,
  int created = 0,
}) => Task(
  id: id,
  creator: creator,
  assignee: assignee,
  status: status,
  due: due,
  created: created,
);

List<int> ids(List<Task> l) => [for (final x in l) x.id];

void main() {
  List<Task> apply(List<Task> list, Task task, [String status = 'active']) =>
      TaskReducer.apply(list, task, as: 'assigned', status: status, user: 'me');

  test('sorted: soonest due first, no due last, then newest', () {
    final list = TaskReducer.sorted([
      t(1),
      t(2, due: 300),
      t(3, due: 100),
      t(4, created: 5),
    ]);
    expect(ids(list), [3, 2, 4, 1]);
  });

  test('task_assigned: a new task joins the assigned tab in order', () {
    final list = apply([t(1, due: 200)], t(2, due: 100));
    expect(ids(list), [2, 1]);
  });

  test('task_assigned for another person does not join my tab', () {
    expect(ids(apply([t(1)], t(2, assignee: 'erin'))), [1]);
  });

  test('task_updated replaces the row in place', () {
    final list = apply([
      t(1, due: 100),
      t(2, due: 200),
    ], t(1, due: 100, status: Task.inProgress));
    expect(ids(list), [1, 2]);
    expect(list.first.status, Task.inProgress);
  });

  test('task_updated to done stays in place under the Active filter', () {
    final list = apply([t(1)], t(1, status: Task.done));
    expect(ids(list), [1]);
    expect(list.single.status, Task.done);
  });

  test('a finished task does not join the Active list', () {
    expect(ids(apply([t(1)], t(2, status: Task.done))), [1]);
    expect(ids(apply([t(1)], t(2, status: Task.done), 'done')), [1, 2]);
    expect(ids(apply([t(1)], t(2, status: Task.done), 'all')), [1, 2]);
  });

  test('a task given away leaves my assigned tab', () {
    expect(ids(apply([t(1), t(2)], t(1, assignee: 'erin'))), [2]);
  });

  test('the created tab follows the creator', () {
    final list = TaskReducer.apply(
      [t(1, creator: 'me')],
      t(2, creator: 'me', assignee: 'erin'),
      as: 'created',
      status: 'active',
      user: 'me',
    );
    expect(ids(list), [1, 2]);
  });

  test('a refresh keeps rows changed here that the page no longer lists', () {
    final fresh = [t(2)];
    final old = [t(1, status: Task.done), t(2)];
    expect(ids(TaskReducer.refreshed(fresh, old, {1})), [1, 2]);
    expect(ids(TaskReducer.refreshed(fresh, old, {})), [2]);
  });

  test('the next page is appended without repeating rows', () {
    expect(ids(TaskReducer.appended([t(1), t(2)], [t(2), t(3)])), [1, 2, 3]);
  });

  test('remove', () {
    expect(ids(TaskReducer.remove([t(1), t(2)], 1)), [2]);
  });
}
