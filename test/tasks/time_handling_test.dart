import 'package:connectum/data/models/task.dart';
import 'package:connectum/features/tasks/models/task_due_label.dart';
import 'package:connectum/features/tasks/models/task_form_rules.dart';
import 'package:connectum/features/tasks/task_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Task task({int? due, String status = 'open'}) =>
    Task(id: 1, title: 't', due: due, status: status);

int ms(DateTime d) => d.millisecondsSinceEpoch;

void main() {
  group('overdue, with a phone clock that is a few minutes wrong', () {
    final due = DateTime(2026, 11, 5, 17, 0);

    test(
      'exactly at the due time it is not yet late; a second after, it is',
      () {
        expect(task(due: ms(due)).isOverdueAt(due), isFalse);
        expect(
          task(due: ms(due)).isOverdueAt(due.add(const Duration(seconds: 1))),
          isTrue,
        );
      },
    );

    test('a clock 5 minutes fast calls a task late 5 minutes early', () {
      final real = due.subtract(const Duration(minutes: 2));
      final fast = real.add(const Duration(minutes: 5));
      expect(task(due: ms(due)).isOverdueAt(real), isFalse);
      expect(task(due: ms(due)).isOverdueAt(fast), isTrue);
    });

    test('a clock 5 minutes slow calls a late task on time', () {
      final real = due.add(const Duration(minutes: 2));
      final slow = real.subtract(const Duration(minutes: 5));
      expect(task(due: ms(due)).isOverdueAt(real), isTrue);
      expect(task(due: ms(due)).isOverdueAt(slow), isFalse);
    });

    test('a finished task is never overdue', () {
      final late = due.add(const Duration(days: 3));
      expect(task(due: ms(due), status: 'done').isOverdueAt(late), isFalse);
      expect(
        task(due: ms(due), status: 'cancelled').isOverdueAt(late),
        isFalse,
      );
      expect(
        task(due: ms(due), status: 'in_progress').isOverdueAt(late),
        isTrue,
      );
    });
  });

  group('due words follow the device calendar day', () {
    final now = DateTime(2026, 11, 5, 0, 3);

    test('today, tomorrow, later, another year', () {
      String? of(DateTime d) => TaskDueLabel.of(
        task(due: ms(DateTime(d.year, d.month, d.day, 23, 59, 59))),
        now,
      );
      expect(of(DateTime(2026, 11, 5)), 'Due today');
      expect(of(DateTime(2026, 11, 6)), 'Due tomorrow');
      expect(of(DateTime(2026, 11, 20)), 'Due 20 Nov');
      expect(of(DateTime(2027, 1, 2)), 'Due 2 Jan 2027');
    });

    test('overdue: same day, one day, many days', () {
      final due = ms(DateTime(2026, 11, 5, 0, 1));
      expect(TaskDueLabel.of(task(due: due), now), 'Overdue today');
      expect(
        TaskDueLabel.of(task(due: ms(DateTime(2026, 11, 4, 23, 0))), now),
        'Overdue by 1 day',
      );
      expect(
        TaskDueLabel.of(task(due: ms(DateTime(2026, 11, 1, 9, 0))), now),
        'Overdue by 4 days',
      );
    });

    test('no due date, no words', () {
      expect(TaskDueLabel.of(task(), now), isNull);
    });

    test('across midnight: the same task flips from today to overdue', () {
      final due = ms(DateTime(2026, 11, 5, 23, 59, 59));
      expect(
        TaskDueLabel.of(task(due: due), DateTime(2026, 11, 5, 23, 59)),
        'Due today',
      );
      expect(
        TaskDueLabel.of(task(due: due), DateTime(2026, 11, 6, 0, 1)),
        'Overdue by 1 day',
      );
    });
  });

  group('the due picker never offers the past', () {
    test('first day is today at any time of day', () {
      for (final now in [
        DateTime(2026, 11, 5, 0, 0, 1),
        DateTime(2026, 11, 5, 12),
        DateTime(2026, 11, 5, 23, 59, 59),
      ]) {
        final form = TaskFormController(
          onSubmit: (_) async => true,
          clock: () => now,
        );
        expect(form.firstDay, DateTime(2026, 11, 5));
      }
    });

    test('an old task keeps its own earlier day so it can be shown', () {
      final old = Task(id: 1, due: ms(DateTime(2026, 11, 1, 23, 59, 59)));
      final form = TaskFormController(
        task: old,
        onSubmit: (_) async => true,
        clock: () => DateTime(2026, 11, 5, 9),
      );
      expect(form.firstDay, DateTime(2026, 11, 1));
    });

    test('a wrong day is refused with the clock the phone has', () {
      final now = DateTime(2026, 11, 5, 0, 2);
      expect(TaskFormRules.dueError(DateTime(2026, 11, 4), now), isNotNull);
      expect(TaskFormRules.dueError(DateTime(2026, 11, 5), now), isNull);
    });

    test(
      'the sent value is 23:59:59 of the local day, later than the server\'s "now" for today',
      () {
        final today = DateTime(2026, 11, 5, 8);
        final sent = TaskFormRules.dueOf(today);
        final serverNowSlightlyAhead = today.add(const Duration(minutes: 10));
        expect(sent, greaterThan(ms(serverNowSlightlyAhead)));
        expect(DateTime.fromMillisecondsSinceEpoch(sent).hour, 23);
      },
    );
  });

  group('field limits at the edge', () {
    test('title 120 ok, 121 refused; description 2000 ok, 2001 refused', () {
      expect(TaskFormRules.titleError('a' * 120), isNull);
      expect(TaskFormRules.titleError('a' * 121), isNotNull);
      expect(TaskFormRules.titleError('   '), isNotNull);
      expect(TaskFormRules.descriptionError('a' * 2000), isNull);
      expect(TaskFormRules.descriptionError('a' * 2001), isNotNull);
    });

    test('a title of 120 letters with spaces around is trimmed first', () {
      expect(TaskFormRules.titleError('  ${'a' * 120}  '), isNull);
    });
  });
}
