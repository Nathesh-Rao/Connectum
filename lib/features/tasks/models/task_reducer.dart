import '../../../data/models/task.dart';

/// Keeps the Tasks lists right when an event or an answer arrives. Pure.
class TaskReducer {
  TaskReducer._();

  /// Soonest due first, no due date last, then newest, then id: the order
  /// the server returns.
  static List<Task> sorted(Iterable<Task> tasks) {
    final list = tasks.toList();
    list.sort((a, b) {
      final noDueA = a.due == null ? 1 : 0;
      final noDueB = b.due == null ? 1 : 0;
      if (noDueA != noDueB) return noDueA - noDueB;
      final byDue = (a.due ?? 0).compareTo(b.due ?? 0);
      if (byDue != 0) return byDue;
      final byCreated = b.created.compareTo(a.created);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });
    return list;
  }

  /// [as]: assigned | created.
  static bool inTab(Task task, String as, String user) =>
      as == 'assigned' ? task.isAssignedTo(user) : task.isCreatedBy(user);

  /// [status]: active | open | in_progress | done | cancelled | all.
  static bool inStatus(Task task, String status) => switch (status) {
    'all' => true,
    'active' => task.isActive,
    _ => task.status == status,
  };

  /// A task arrives from an event or from my own answer. It leaves a tab it
  /// no longer belongs to (given away), changes in place where it is shown
  /// (even if the filter would no longer list it, so a row does not vanish
  /// under the finger), and joins a tab when it matches the tab and filter.
  static List<Task> apply(
    List<Task> list,
    Task task, {
    required String as,
    required String status,
    required String user,
  }) {
    if (!inTab(task, as, user)) return remove(list, task.id);
    if (list.any((t) => t.id == task.id)) {
      return [for (final t in list) t.id == task.id ? task : t];
    }
    if (!inStatus(task, status)) return list;
    return sorted([...list, task]);
  }

  static List<Task> remove(List<Task> list, int id) => [
    for (final t in list)
      if (t.id != id) t,
  ];

  /// A first page read again. Rows changed here ([kept]) that the page no
  /// longer lists stay until the person leaves or changes the filter.
  static List<Task> refreshed(List<Task> fresh, List<Task> old, Set<int> kept) {
    final ids = {for (final t in fresh) t.id};
    return sorted([
      ...fresh,
      for (final t in old)
        if (kept.contains(t.id) && !ids.contains(t.id)) t,
    ]);
  }

  /// The next page after the rows already shown.
  static List<Task> appended(List<Task> shown, List<Task> page) {
    final ids = {for (final t in shown) t.id};
    return [
      ...shown,
      for (final t in page)
        if (!ids.contains(t.id)) t,
    ];
  }
}
