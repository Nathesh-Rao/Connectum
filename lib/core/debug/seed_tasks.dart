import '../../data/models/approval.dart';
import '../../features/chats/models/chat_person.dart';
import '../../data/models/task.dart';
import '../../data/socket/socket_service.dart';

/// Debug only (`/debug/tasks`, see "Before release" in CLAUDE.md): sample
/// tasks and requests in memory, answered in place of the server, so Tasks
/// and Approvals can be tried with no connection.
class SeedTasks {
  SeedTasks._();

  static bool isActive = false;

  /// The next sample call fails with this error (rate_limited, busy, ...).
  static SocketCallError? nextError;

  static const me = 'me';
  static List<Task> tasks = [];
  static List<Approval> requests = [];
  static int _seq = 100;

  static int get _now => DateTime.now().millisecondsSinceEpoch;
  static int _in(int hours) => _now + hours * 3600000;

  static void start() {
    isActive = true;
    nextError = null;
    tasks = [
      Task(
        id: 1,
        title: 'Send the Q4 expense report',
        description: 'Include the travel receipts from October.',
        creator: 'priya',
        creatorName: 'Priya S',
        assignee: me,
        assigneeName: 'Me',
        due: _in(-5),
        priority: 'high',
        created: _in(-72),
        updated: _in(-72),
      ),
      Task(
        id: 2,
        title: 'Review the vendor contract',
        creator: 'sam',
        creatorName: 'Sam W',
        assignee: me,
        assigneeName: 'Me',
        due: _in(20),
        status: Task.inProgress,
        created: _in(-30),
        updated: _in(-3),
      ),
      Task(
        id: 3,
        title: 'Book the team offsite',
        creator: 'priya',
        creatorName: 'Priya S',
        assignee: me,
        assigneeName: 'Me',
        priority: 'low',
        created: _in(-10),
        updated: _in(-10),
      ),
      Task(
        id: 4,
        title: 'Update the onboarding checklist',
        description: 'Add the new laptop steps.',
        creator: me,
        creatorName: 'Me',
        assignee: 'erin',
        assigneeName: 'Erin E',
        due: _in(48),
        created: _in(-8),
        updated: _in(-8),
      ),
      Task(
        id: 5,
        title: 'Collect desk numbers',
        creator: me,
        creatorName: 'Me',
        assignee: 'sam',
        assigneeName: 'Sam W',
        status: Task.done,
        created: _in(-90),
        updated: _in(-20),
        doneTs: _in(-20),
      ),
    ];
    requests = [
      Approval(
        id: 11,
        type: 'submission',
        from: 'emma',
        fromName: 'Emma Employee',
        subject: 'emma',
        subjectName: 'Emma Employee',
        approvers: const [me],
        direction: Approval.incoming,
        canRespond: true,
        createdTs: _in(-2),
        caption: 'Expense claim',
        message: 'Emma Employee submitted Expense claim',
        stage: 1,
        stages: 2,
        lines: const [
          ApprovalLine('Amount', '120'),
          ApprovalLine('Category', 'Travel'),
        ],
      ),
      Approval(
        id: 12,
        type: 'group_invite',
        from: 'sam',
        fromName: 'Sam W',
        subject: me,
        subjectName: 'Me',
        approvers: const [me],
        direction: Approval.incoming,
        canRespond: true,
        createdTs: _in(-6),
        message: 'Sam W invites you to a group',
      ),
      Approval(
        id: 13,
        type: 'submission',
        from: me,
        fromName: 'Me',
        subject: me,
        subjectName: 'Me',
        approvers: const ['meg', 'raj'],
        direction: Approval.outgoing,
        createdTs: _in(-4),
        caption: 'Leave request',
        message: 'Me submitted Leave request',
        stage: 1,
        stages: 1,
        lines: const [ApprovalLine('Days', '3')],
      ),
      Approval(
        id: 14,
        type: 'membership',
        from: 'lee',
        fromName: 'Lee K',
        subject: 'lee',
        subjectName: 'Lee K',
        approvers: const [me],
        status: Approval.accepted,
        direction: Approval.incoming,
        createdTs: _in(-50),
        resolvedTs: _in(-40),
        resolvedBy: me,
        resolvedByName: 'Me',
        message: 'Lee K asked to join',
      ),
    ];
  }

  static void stop() {
    isActive = false;
    nextError = null;
    tasks = [];
    requests = [];
  }

  static void failIfAsked() {
    final error = nextError;
    if (error == null) return;
    nextError = null;
    throw error;
  }

  static int nextId() => ++_seq;

  static const people = [
    ChatPerson(
      username: 'erin',
      name: 'Erin E',
      source: 'colleague',
      detail: 'Designer',
    ),
    ChatPerson(
      username: 'priya',
      name: 'Priya S',
      source: 'colleague',
      detail: 'Finance',
    ),
    ChatPerson(
      username: 'sam',
      name: 'Sam W',
      source: 'colleague',
      detail: 'Sales',
    ),
  ];

  static TaskPage taskPage(String as, String status, int offset, int limit) {
    failIfAsked();
    bool inStatus(Task t) => switch (status) {
      'all' => true,
      'active' => t.isActive,
      _ => t.status == status,
    };
    final mine = [
      for (final t in tasks)
        if (inStatus(t) &&
            (as == 'all' ||
                (as == 'assigned' && t.isAssignedTo(me)) ||
                (as == 'created' && t.isCreatedBy(me))))
          t,
    ];
    mine.sort((a, b) {
      final x = a.due == null ? 1 : 0;
      final y = b.due == null ? 1 : 0;
      if (x != y) return x - y;
      return (a.due ?? 0).compareTo(b.due ?? 0);
    });
    final page = mine.skip(offset).take(limit).toList();
    return TaskPage(
      page,
      total: mine.length,
      hasMore: offset + page.length < mine.length,
    );
  }

  static ApprovalPage requestPage(String status, int offset, int limit) {
    failIfAsked();
    final all = [
      for (final r in requests)
        if (status == 'all' || r.status == status) r,
    ];
    final page = all.skip(offset).take(limit).toList();
    return ApprovalPage(
      page,
      total: all.length,
      hasMore: offset + page.length < all.length,
    );
  }
}
