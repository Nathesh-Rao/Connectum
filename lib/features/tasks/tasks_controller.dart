import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_notice_card.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/task.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/socket/call_problem.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import '../chats/models/chat_person.dart';
import '../tickets/tickets_controller.dart';
import 'models/task_actions.dart';
import 'models/task_reducer.dart';
import 'task_form_controller.dart';
import 'task_people_controller.dart';
import 'tasks_texts.dart';
import 'widgets/task_detail_sheet.dart';

/// One tab's list.
class TaskList {
  final items = <Task>[].obs;
  final viewState = AppViewState.loading.obs;
  final hasMore = false.obs;
  final isLoadingMore = false.obs;

  /// Rows read from the server so far (the next page's `offset`).
  int loaded = 0;

  /// The newest read; an older answer arriving later is dropped.
  int seq = 0;
}

/// The Tasks screen: "Assigned to me" and "Created by me", a status filter,
/// and every action on a task. Writes are sent once and never replayed: a
/// failure is shown with the server's own words and a manual Retry.
class TasksController extends GetxController
    with GetTickerProviderStateMixin {
  TasksController({
    required this.tasks,
    required this.people,
    required this.connectivity,
    required this.tickets,
  });

  final TaskRepository tasks;
  final GroupRepository people;
  final ConnectivityService connectivity;

  /// The Tickets section: a third list, never mixed with the tasks.
  final TicketsController tickets;

  /// The route argument that opens the Tickets section.
  static const showTickets = 'tickets';

  static const tabs = ['assigned', 'created'];
  static const filters = ['active', 'done', 'cancelled', 'all'];
  static const filterLabels = [
    TasksTexts.filterActive,
    TasksTexts.filterDone,
    TasksTexts.filterCancelled,
    TasksTexts.filterAll,
  ];

  late final tabController = TabController(length: tabs.length, vsync: this);

  /// 0 = To-dos, 1 = Tickets.
  late final sectionController = TabController(length: 2, vsync: this);
  final selectedFilter = 0.obs;
  final lists = {for (final t in tabs) t: TaskList()};

  /// A write is in flight: no second one starts.
  final isBusy = false.obs;

  /// Rows I changed that the filter would no longer list; they stay until the
  /// person leaves or changes the filter.
  final _kept = <int>{};
  StreamSubscription<TaskChange>? _changes;
  StreamSubscription<void>? _refreshes;
  StreamSubscription<int>? _openRequests;

  String get me => tasks.me;
  String get status => filters[selectedFilter.value];

  @override
  void onInit() {
    super.onInit();
    _changes = tasks.changes.listen(_onChange);
    _refreshes = tasks.refreshes.listen((_) => unawaited(refreshAll()));
    _openRequests = tasks.openRequests.listen((id) => unawaited(openTask(id)));
    unawaited(refreshAll());
    final id = Get.arguments;
    if (id is int) unawaited(openTask(id));
    if (id == showTickets) sectionController.index = 1;
  }

  /// Opens the task [id] of a notice: from the lists, else read with
  /// `task.get`. A task that is gone says so.
  Future<void> openTask(int id) async {
    if (find(id) == null) {
      try {
        _apply(await tasks.get(id));
      } on SocketCallError {
        AppNotices.info('That task is no longer available.');
        return;
      }
    }
    final context = Get.context;
    if (context == null || !context.mounted) return;
    await TaskDetailSheet.show(context, this, id);
  }

  @override
  void onClose() {
    _openRequests?.cancel();
    _changes?.cancel();
    _refreshes?.cancel();
    tabController.dispose();
    sectionController.dispose();
    super.onClose();
  }

  Task? find(int id) {
    for (final list in lists.values) {
      for (final t in list.items) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  TaskActions actionsOf(Task t) => TaskActions.of(t, me);

  // ---- reading ---------------------------------------------------------------

  Future<void> refreshAll() async {
    await Future.wait([for (final as in tabs) load(as)]);
  }

  /// The first page of a tab, replacing what is shown. [isQuiet]: a refresh
  /// behind the screen never turns a list into an error.
  Future<void> load(String as, {bool isQuiet = true}) async {
    final list = lists[as]!;
    final seq = ++list.seq;
    final wasEmpty = list.items.isEmpty;
    if (wasEmpty && list.viewState.value != AppViewState.content) {
      list.viewState.value = AppViewState.loading;
    }
    try {
      final page = await tasks.list(as: as, status: status);
      if (seq != list.seq) return;
      list.items.assignAll(
        TaskReducer.refreshed(page.tasks, list.items.toList(), _kept),
      );
      list.loaded = page.tasks.length;
      list.hasMore.value = page.hasMore;
      list.viewState.value = list.items.isEmpty
          ? AppViewState.empty
          : AppViewState.content;
    } on SocketCallError catch (e) {
      if (seq != list.seq) return;
      if (list.items.isNotEmpty) {
        list.viewState.value = AppViewState.content;
        if (!isQuiet) _tell(CallProblem.of(e), retry: () => load(as));
      } else {
        list.viewState.value =
            connectivity.state.value == AppConnectivity.online
            ? AppViewState.error
            : AppViewState.offline;
      }
    }
  }

  Future<void> loadMore(String as) async {
    final list = lists[as]!;
    if (list.isLoadingMore.value || !list.hasMore.value) return;
    list.isLoadingMore.value = true;
    try {
      final page = await tasks.list(
        as: as,
        status: status,
        offset: list.loaded,
      );
      list.items.assignAll(TaskReducer.appended(list.items, page.tasks));
      list.loaded += page.tasks.length;
      list.hasMore.value = page.hasMore;
    } on SocketCallError catch (e) {
      _tell(CallProblem.of(e), retry: () => loadMore(as));
    } finally {
      list.isLoadingMore.value = false;
    }
  }

  void selectFilter(int index) {
    if (index == selectedFilter.value) return;
    selectedFilter.value = index;
    _kept.clear();
    for (final list in lists.values) {
      list.items.clear();
      list.hasMore.value = false;
      list.loaded = 0;
      list.seq++;
      list.viewState.value = AppViewState.loading;
    }
    unawaited(refreshAll());
  }

  // ---- events and answers ----------------------------------------------------

  void _onChange(TaskChange change) {
    _apply(change.task);
  }

  /// Puts [task] into each tab where it belongs, or takes it out.
  void _apply(Task task) {
    for (final entry in lists.entries) {
      final list = entry.value;
      final next = TaskReducer.apply(
        list.items.toList(),
        task,
        as: entry.key,
        status: status,
        user: me,
      );
      final isShown = next.any((t) => t.id == task.id);
      if (isShown && !TaskReducer.inStatus(task, status)) _kept.add(task.id);
      list.items.assignAll(next);
      if (next.isNotEmpty) {
        list.viewState.value = AppViewState.content;
      } else if (list.viewState.value == AppViewState.content) {
        list.viewState.value = AppViewState.empty;
      }
    }
  }

  void _remove(int id) {
    for (final list in lists.values) {
      list.items.assignAll(TaskReducer.remove(list.items.toList(), id));
      if (list.items.isEmpty && list.viewState.value == AppViewState.content) {
        list.viewState.value = AppViewState.empty;
      }
    }
  }

  // ---- actions ---------------------------------------------------------------

  Future<bool> start(Task t) => _setStatus(t, Task.inProgress);
  Future<bool> complete(Task t) => _setStatus(t, Task.done);
  Future<bool> cancel(Task t) => _setStatus(t, Task.cancelled);
  Future<bool> reopen(Task t) => _setStatus(t, Task.open);

  Future<bool> _setStatus(Task t, String next) => _write(
    () async => _apply(await tasks.update(t.id, {'status': next})),
    retry: () => _setStatus(t, next),
    taskId: t.id,
  );

  Future<bool> sendTo(Task t, ChatPerson person) => _write(
    () async => _apply(await tasks.send(t.id, person.username)),
    retry: () => sendTo(t, person),
    taskId: t.id,
    done: TasksTexts.sentDone,
  );

  Future<bool> _create(Map<String, dynamic> fields) => _write(
    () async => _apply(await tasks.create(fields)),
    retry: () => _create(fields),
    done: TasksTexts.createdDone,
  );

  Future<bool> _update(Task t, Map<String, dynamic> fields) => _write(
    () async => _apply(await tasks.update(t.id, fields)),
    retry: () => _update(t, fields),
    taskId: t.id,
    done: TasksTexts.savedDone,
  );

  /// One write at a time. A failure is told with the server's text; a Retry
  /// button only when nothing reached the server or it said to slow down. A
  /// refusal or an unknown outcome reads the task (or the lists) again.
  Future<bool> _write(
    Future<void> Function() call, {
    required Future<void> Function() retry,
    int? taskId,
    String? done,
  }) async {
    if (isBusy.value) return false;
    isBusy.value = true;
    try {
      await call();
      if (done != null) AppNotices.success(done);
      return true;
    } on SocketCallError catch (e) {
      final problem = CallProblem.of(e, isWrite: true);
      _tell(problem, retry: retry);
      if (problem.shouldRefresh) unawaited(_recover(problem, taskId));
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  Future<void> _recover(CallProblem problem, int? taskId) async {
    if (taskId == null || problem.kind == CallProblemKind.unknownOutcome) {
      await refreshAll();
      return;
    }
    if (problem.kind == CallProblemKind.notFound) {
      _remove(taskId);
      return;
    }
    try {
      _apply(await tasks.get(taskId));
    } on SocketCallError catch (e) {
      if (e.code == 'not_found') _remove(taskId);
    }
  }

  void _tell(CallProblem problem, {required Future<void> Function() retry}) {
    AppNotices.show(
      problem.text,
      variant:
          problem.kind == CallProblemKind.unknownOutcome || problem.canRetry
          ? AppNoticeVariant.warning
          : AppNoticeVariant.error,
      actionLabel: problem.canRetry ? TasksTexts.retry : null,
      onAction: problem.canRetry ? () => unawaited(retry()) : null,
    );
  }

  // ---- forms -----------------------------------------------------------------

  TaskFormController newForm() => TaskFormController(onSubmit: _create);

  TaskFormController editForm(Task t) =>
      TaskFormController(task: t, onSubmit: (fields) => _update(t, fields));

  TaskPeopleController newPeople() => TaskPeopleController(people);
}
