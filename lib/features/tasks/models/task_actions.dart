import '../../../data/models/task.dart';

/// What [user] may do with a task, worked out from the data. The server
/// stays the judge: it can still refuse, and its text is shown.
class TaskActions {
  const TaskActions._({
    required this.canEdit,
    required this.canStart,
    required this.canComplete,
    required this.canCancel,
    required this.canSend,
    required this.canReopen,
  });

  /// Any field (creator, task not finished).
  final bool canEdit;

  /// Open -> in progress.
  final bool canStart;

  /// Open or in progress -> done.
  final bool canComplete;

  /// Only the creator cancels.
  final bool canCancel;

  /// Only the creator gives it to someone else.
  final bool canSend;

  /// A finished task is edited only after the creator reopens it.
  final bool canReopen;

  bool get hasAny =>
      canEdit || canStart || canComplete || canCancel || canSend || canReopen;

  static TaskActions of(Task task, String user) {
    final isCreator = task.isCreatedBy(user);
    final isAssignee = task.isAssignedTo(user);
    final canMove = isCreator || isAssignee;
    return TaskActions._(
      canEdit: isCreator && !task.isFinished,
      canStart: canMove && task.status == Task.open,
      canComplete: canMove && task.isActive,
      canCancel: isCreator && task.isActive,
      canSend: isCreator && task.isActive,
      canReopen: isCreator && task.isFinished,
    );
  }
}
