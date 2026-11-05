import 'package:connectum/data/models/task.dart';
import 'package:connectum/features/tasks/models/task_form_rules.dart';
import 'package:connectum/features/tasks/task_form_controller.dart';
import 'package:connectum/features/tasks/tasks_texts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 5, 12);

  test('title: required, at most 120', () {
    expect(TaskFormRules.titleError(''), TasksTexts.titleRequired);
    expect(TaskFormRules.titleError('   '), TasksTexts.titleRequired);
    expect(TaskFormRules.titleError('a' * 120), isNull);
    expect(TaskFormRules.titleError('a' * 121), TasksTexts.titleTooLong);
    expect(TaskFormRules.titleError('  ${'a' * 120}  '), isNull);
  });

  test('description: optional, at most 2000', () {
    expect(TaskFormRules.descriptionError(''), isNull);
    expect(TaskFormRules.descriptionError('a' * 2000), isNull);
    expect(
      TaskFormRules.descriptionError('a' * 2001),
      TasksTexts.descriptionTooLong,
    );
  });

  test('due: today is fine, yesterday is not, none is fine', () {
    expect(TaskFormRules.dueError(null, now), isNull);
    expect(TaskFormRules.dueError(DateTime(2026, 11, 5), now), isNull);
    expect(TaskFormRules.dueError(DateTime(2026, 11, 6), now), isNull);
    expect(
      TaskFormRules.dueError(DateTime(2026, 11, 4), now),
      TasksTexts.duePast,
    );
  });

  test('due: an unchanged past date of an existing task is accepted', () {
    final old = DateTime(2026, 10, 1);
    expect(TaskFormRules.dueError(old, now, unchanged: old), isNull);
    expect(
      TaskFormRules.dueError(DateTime(2026, 10, 2), now, unchanged: old),
      TasksTexts.duePast,
    );
  });

  test('the due value is the end of the chosen day, so today is not past', () {
    final due = TaskFormRules.dueOf(DateTime(2026, 11, 5));
    expect(due, greaterThan(now.millisecondsSinceEpoch));
  });

  test('create fields: trimmed, optional parts left out', () {
    expect(
      TaskFormRules.createFields(
        title: '  Pay rent ',
        description: '  ',
        due: null,
        priority: 'normal',
      ),
      {'title': 'Pay rent', 'priority': 'normal'},
    );
    final full = TaskFormRules.createFields(
      title: 'x',
      description: 'd',
      due: DateTime(2026, 11, 6),
      priority: 'high',
      assignee: 'erin',
    );
    expect(full['assignee'], 'erin');
    expect(full['description'], 'd');
    expect(full['due'], isA<int>());
  });

  test('update fields: only what changed', () {
    const old = Task(id: 1, title: 'A', description: 'd', priority: 'low');
    expect(
      TaskFormRules.changes(
        old,
        title: 'A',
        description: 'd',
        due: null,
        priority: 'low',
      ),
      isEmpty,
    );
    expect(
      TaskFormRules.changes(
        old,
        title: 'B',
        description: 'd',
        due: null,
        priority: 'high',
      ),
      {'title': 'B', 'priority': 'high'},
    );
  });

  test('the form shows errors on submit and sends nothing', () async {
    var sent = 0;
    final form = TaskFormController(
      onSubmit: (_) async {
        sent++;
        return true;
      },
      clock: () => now,
    );
    expect(await form.submit(), isFalse);
    expect(form.titleError.value, TasksTexts.titleRequired);
    expect(sent, 0);
    form.title.text = 'Real title';
    form.onChanged();
    expect(form.titleError.value, isNull);
    expect(await form.submit(), isTrue);
    expect(sent, 1);
  });

  test('a second tap while a create is in flight sends nothing', () async {
    var sent = 0;
    final form = TaskFormController(
      onSubmit: (_) async {
        sent++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return true;
      },
      clock: () => now,
    )..title.text = 'Once only';
    final first = form.submit();
    final second = form.submit();
    expect(await second, isFalse);
    expect(await first, isTrue);
    expect(sent, 1);
    expect(form.isSubmitting.value, isFalse);
  });

  test('editing with no change sends nothing', () async {
    var sent = 0;
    final form = TaskFormController(
      task: const Task(id: 3, title: 'Same'),
      onSubmit: (_) async {
        sent++;
        return true;
      },
      clock: () => now,
    );
    expect(await form.submit(), isTrue);
    expect(sent, 0);
  });
}
