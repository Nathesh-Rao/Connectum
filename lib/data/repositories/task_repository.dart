import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_tasks.dart';
import '../models/task.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';

/// A `task_assigned` or `task_updated` event.
class TaskChange {
  const TaskChange(this.task, {required this.isAssigned});

  final Task task;
  final bool isAssigned;
}

/// The `task.*` calls and events. `task.*` takes no `cid`, so a write is sent
/// once and never replayed by the app: a failure goes back to the person,
/// who decides to retry. Nothing is kept here; the screen owns its lists and
/// reads again when [refreshes] fires (reconnect, resume, any task event,
/// coalesced), because events sent while offline are lost.
class TaskRepository extends GetxService with WidgetsBindingObserver {
  TaskRepository(this._socket, this._store);

  final SocketService _socket;
  final SessionStore _store;

  static const pageSize = 50;
  static const burst = Duration(milliseconds: 150);

  final _changes = StreamController<TaskChange>.broadcast();
  final _refreshes = StreamController<void>.broadcast();
  Timer? _burst;
  StreamSubscription<Map<String, dynamic>>? _events;
  StreamSubscription<void>? _online;

  Stream<TaskChange> get changes => _changes.stream;

  final _openRequests = StreamController<int>.broadcast();

  /// A tap asked to open this task while the Tasks screen is up.
  Stream<int> get openRequests => _openRequests.stream;

  void requestOpen(int id) => _openRequests.add(id);

  /// Read the first pages again.
  Stream<void> get refreshes => _refreshes.stream;

  String get me => (_store.userId ?? SeedTasks.me).toLowerCase();

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _events = _socket.events.listen(onEvent);
    _online = _socket.onOnline.listen((_) => scheduleRefresh());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _burst?.cancel();
    _events?.cancel();
    _online?.cancel();
    _changes.close();
    _openRequests.close();
    _refreshes.close();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) scheduleRefresh();
  }

  void scheduleRefresh() {
    _burst?.cancel();
    _burst = Timer(burst, () {
      if (!_refreshes.isClosed) _refreshes.add(null);
    });
  }

  /// Public so the debug page and tests can feed it events.
  void onEvent(Map<String, dynamic> e) {
    if (e['type'] != 'sd_event') return;
    final event = e['event'];
    if (event != 'task_assigned' && event != 'task_updated') return;
    final data = e['data'];
    final task = data is Map ? Task.tryParse(data['task']) : null;
    if (task != null) {
      _changes.add(TaskChange(task, isAssigned: event == 'task_assigned'));
    }
    scheduleRefresh();
  }

  // ---- calls -----------------------------------------------------------------

  /// [as]: assigned | created | all. [status]: active | open | in_progress |
  /// done | cancelled | all.
  Future<TaskPage> list({
    required String as,
    String status = 'active',
    int offset = 0,
  }) async {
    if (SeedTasks.isActive) {
      return SeedTasks.taskPage(as, status, offset, pageSize);
    }
    final data = await _socket.sdCall('task.list', {
      'as': as,
      'status': status,
      'limit': pageSize,
      if (offset > 0) 'offset': offset,
    });
    return TaskPage.parse(data);
  }

  Future<Task> create(Map<String, dynamic> fields) async {
    if (SeedTasks.isActive) {
      SeedTasks.failIfAsked();
      final assignee = '${fields['assignee'] ?? SeedTasks.me}';
      final now = DateTime.now().millisecondsSinceEpoch;
      final task = Task(
        id: SeedTasks.nextId(),
        title: '${fields['title']}',
        description: '${fields['description'] ?? ''}',
        creator: SeedTasks.me,
        creatorName: 'Me',
        assignee: assignee,
        assigneeName: assignee == SeedTasks.me ? 'Me' : assignee,
        due: fields['due'] as int?,
        priority: '${fields['priority'] ?? 'normal'}',
        created: now,
        updated: now,
      );
      SeedTasks.tasks = [...SeedTasks.tasks, task];
      return task;
    }
    return _task(await _socket.sdCall('task.create', fields));
  }

  Future<Task> update(int id, Map<String, dynamic> fields) async {
    if (SeedTasks.isActive) {
      SeedTasks.failIfAsked();
      final old = SeedTasks.tasks.firstWhere((t) => t.id == id);
      final status = fields['status'] as String?;
      final next = old.copyWith(
        status: status,
        updated: DateTime.now().millisecondsSinceEpoch,
      );
      SeedTasks.tasks = [
        for (final t in SeedTasks.tasks) t.id == id ? next : t,
      ];
      return next;
    }
    return _task(await _socket.sdCall('task.update', {'id': id, ...fields}));
  }

  Future<Task> send(int id, String to) async {
    if (SeedTasks.isActive) {
      SeedTasks.failIfAsked();
      final old = SeedTasks.tasks.firstWhere((t) => t.id == id);
      final next = Task(
        id: old.id,
        title: old.title,
        description: old.description,
        creator: old.creator,
        creatorName: old.creatorName,
        assignee: to,
        assigneeName: to,
        due: old.due,
        priority: old.priority,
        status: old.status,
        created: old.created,
        updated: DateTime.now().millisecondsSinceEpoch,
      );
      SeedTasks.tasks = [
        for (final t in SeedTasks.tasks) t.id == id ? next : t,
      ];
      return next;
    }
    return _task(await _socket.sdCall('task.send', {'id': id, 'to': to}));
  }

  /// One task (`task.get {id}`).
  Future<Task> get(int id) async {
    if (SeedTasks.isActive) {
      SeedTasks.failIfAsked();
      return SeedTasks.tasks.firstWhere((t) => t.id == id);
    }
    return _task(await _socket.sdCall('task.get', {'id': id}));
  }

  /// `{task: view}` or a bare view.
  static Task _task(Map<String, dynamic> data) =>
      Task.tryParse(data['task']) ??
      Task.tryParse(data) ??
      (throw const SocketCallError('error', 'The server sent no task.'));
}
