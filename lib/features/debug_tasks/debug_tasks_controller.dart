import 'package:get/get.dart';

import '../../core/debug/seed_tasks.dart';
import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_notices.dart';
import '../../data/models/approval.dart';
import '../../data/models/task.dart';
import '../../data/repositories/approval_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/socket/socket_service.dart';

/// Tasks and Approvals with sample data and injected events, no server. Debug
/// builds only (see "Before release" in CLAUDE.md).
class DebugTasksController extends GetxController {
  DebugTasksController({required this.tasks, required this.approvals});

  final TaskRepository tasks;
  final ApprovalRepository approvals;

  final isSample = SeedTasks.isActive.obs;
  final nextFailure = RxnString();

  int get _now => DateTime.now().millisecondsSinceEpoch;

  void toggleSample(bool value) {
    if (value) {
      SeedTasks.start();
    } else {
      SeedTasks.stop();
    }
    isSample.value = value;
    tasks.scheduleRefresh();
    approvals.scheduleRefresh();
  }

  void openTasks() => Get.toNamed(AppRoutes.tasks);
  void openApprovals() => Get.toNamed(AppRoutes.approvals);

  static const failures = {
    'rate_limited': 'Too many tasks this hour; try later.',
    'busy': 'Too many commands -- slow down and retry.',
    'forbidden': 'Only the person who created the task can edit it.',
    'not_found': 'No such task.',
    'already_resolved': 'That request has already been answered.',
    'invalid': 'A finished task cannot be edited; reopen it first.',
  };

  /// The next sample call fails the way the server would answer.
  void failNext(String code) {
    SeedTasks.nextError = SocketCallError(code, failures[code]!);
    nextFailure.value = code;
    AppNotices.info('The next call fails with $code.');
  }

  void clearFailure() {
    SeedTasks.nextError = null;
    nextFailure.value = null;
  }

  Map<String, dynamic> _taskJson(Task t) => {
    'id': t.id,
    'title': t.title,
    'description': t.description,
    'creator': t.creator,
    'creatorName': t.creatorName,
    'assignee': t.assignee,
    'assigneeName': t.assigneeName,
    'due': t.due,
    'priority': t.priority,
    'status': t.status,
    'created': t.created,
    'updated': t.updated,
  };

  void _taskEvent(String event, Task t) {
    SeedTasks.tasks = [
      for (final x in SeedTasks.tasks)
        if (x.id != t.id) x,
      t,
    ];
    tasks.onEvent({
      'type': 'sd_event',
      'event': event,
      'data': {'task': _taskJson(t)},
    });
  }

  void taskAssigned() => _taskEvent(
    'task_assigned',
    Task(
      id: SeedTasks.nextId(),
      title: 'Prepare the board deck',
      creator: 'priya',
      creatorName: 'Priya S',
      assignee: SeedTasks.me,
      assigneeName: 'Me',
      due: _now + 86400000,
      priority: 'high',
      created: _now,
      updated: _now,
    ),
  );

  /// Erin finishes the task I gave her.
  void taskUpdated() {
    final old = SeedTasks.tasks.where((t) => t.id == 4).firstOrNull;
    if (old == null) return;
    _taskEvent(
      'task_updated',
      old.copyWith(status: Task.done, updated: _now, doneTs: _now),
    );
  }

  void requestCreated() {
    final id = SeedTasks.nextId();
    final json = {
      'id': id,
      'type': 'submission',
      'status': 'pending',
      'from': 'lee',
      'fromName': 'Lee K',
      'subject': 'lee',
      'subjectName': 'Lee K',
      'approvers': [SeedTasks.me],
      'createdTs': _now,
      'resolvedTs': null,
      'resolvedBy': null,
      'data': {
        'caption': 'Purchase order',
        'message': 'Lee K submitted Purchase order',
        'stage': 1,
        'stages': 1,
        'summary': [
          {'caption': 'Amount', 'value': '800'},
        ],
      },
    };
    final request = Approval.tryParse({
      ...json,
      'direction': 'incoming',
      'canRespond': true,
    });
    if (request != null) SeedTasks.requests = [...SeedTasks.requests, request];
    approvals.onEvent({
      'type': 'sd_event',
      'event': 'request_created',
      'data': json,
    });
  }

  /// Meg answers the leave request I sent.
  void requestResolved() {
    final old = SeedTasks.requests.where((r) => r.id == 13).firstOrNull;
    if (old == null) return;
    final done = old.copyWith(
      status: Approval.accepted,
      canRespond: false,
      resolvedTs: _now,
      resolvedBy: 'meg',
      resolvedByName: 'Meg M',
    );
    SeedTasks.requests = [
      for (final r in SeedTasks.requests) r.id == 13 ? done : r,
    ];
    approvals.onEvent({
      'type': 'sd_event',
      'event': 'request_resolved',
      'data': {
        'id': 13,
        'type': 'submission',
        'status': 'accepted',
        'from': SeedTasks.me,
        'fromName': 'Me',
        'subject': SeedTasks.me,
        'approvers': ['meg', 'raj'],
        'createdTs': old.createdTs,
        'resolvedTs': _now,
        'resolvedBy': 'meg',
        'resolvedByName': 'Meg M',
        'data': {'caption': 'Leave request'},
      },
    });
  }
}
