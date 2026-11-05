import 'ids.dart';

/// One to-do (`task.*`). Every field but [id] may be missing.
class Task {
  const Task({
    required this.id,
    this.title = '',
    this.description = '',
    this.creator = '',
    this.assignee = '',
    this.due,
    this.priority = 'normal',
    this.status = 'open',
    this.created = 0,
    this.updated = 0,
    this.doneTs,
    this.creatorName = '',
    this.assigneeName = '',
  });

  static const open = 'open';
  static const inProgress = 'in_progress';
  static const done = 'done';
  static const cancelled = 'cancelled';
  static const priorities = ['low', 'normal', 'high'];

  final int id;
  final String title;
  final String description;
  final String creator;
  final String assignee;

  /// Milliseconds since the epoch; null when the task has no due date.
  final int? due;
  final String priority;
  final String status;
  final int created;
  final int updated;
  final int? doneTs;
  final String creatorName;
  final String assigneeName;

  bool get isActive => status == open || status == inProgress;
  bool get isFinished => status == done || status == cancelled;
  bool get isHigh => priority == 'high';

  /// The server's own flag is only as fresh as the last read, so it is worked
  /// out again from [due].
  bool isOverdueAt(DateTime now) =>
      isActive && due != null && due! < now.millisecondsSinceEpoch;

  String get creatorLabel => creatorName.isEmpty ? creator : creatorName;
  String get assigneeLabel => assigneeName.isEmpty ? assignee : assigneeName;

  bool isCreatedBy(String user) => _same(creator, user);
  bool isAssignedTo(String user) => _same(assignee, user);

  static bool _same(String a, String b) =>
      a.isNotEmpty && a.toLowerCase() == b.toLowerCase();

  Task copyWith({String? status, int? updated, int? doneTs}) => Task(
    id: id,
    title: title,
    description: description,
    creator: creator,
    assignee: assignee,
    due: due,
    priority: priority,
    status: status ?? this.status,
    created: created,
    updated: updated ?? this.updated,
    doneTs: doneTs ?? this.doneTs,
    creatorName: creatorName,
    assigneeName: assigneeName,
  );

  /// Null when the map has no usable id.
  static Task? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = idNumber(json['id']);
    if (id == null) return null;
    final status = _text(json['status']);
    final priority = _text(json['priority']);
    return Task(
      id: id,
      title: _text(json['title']),
      description: _text(json['description']),
      creator: _text(json['creator']),
      assignee: _text(json['assignee']),
      due: _intOrNull(json['due']),
      priority: priorities.contains(priority) ? priority : 'normal',
      status: status.isEmpty ? open : status,
      created: intOf(json['created']),
      updated: intOf(json['updated']),
      doneTs: _intOrNull(json['doneTs']),
      creatorName: _text(json['creatorName']),
      assigneeName: _text(json['assigneeName']),
    );
  }

  static String _text(Object? v) => v is String ? v : idText(v);

  static int? _intOrNull(Object? v) =>
      v is num ? v.toInt() : int.tryParse(idText(v));
}

/// One page of `task.list`.
class TaskPage {
  const TaskPage(this.tasks, {required this.total, required this.hasMore});

  final List<Task> tasks;
  final int total;
  final bool hasMore;

  static TaskPage parse(Map<String, dynamic> data) {
    final raw = data['tasks'];
    final tasks = <Task>[
      if (raw is List)
        for (final j in raw) ?Task.tryParse(j),
    ];
    return TaskPage(
      tasks,
      total: data['total'] == null ? tasks.length : intOf(data['total']),
      hasMore: data['hasMore'] == true,
    );
  }
}
