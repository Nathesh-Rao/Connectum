/// Which live events make the Inbox read again: the web's `isWorkChange`
/// rule `^(task_|ticket_|submissions?_|resync)`. Approval events
/// (`request_created`, `request_resolved`) are not in it: the
/// ApprovalRepository takes them.
class InboxLiveRule {
  InboxLiveRule._();

  static final _work = RegExp(r'^(task_|ticket_|submissions?_|resync)');

  /// The name of a socket event: the `event` of an `sd_event`, else its type.
  static String nameOf(Map<String, dynamic> e) {
    final name = e['type'] == 'sd_event' ? e['event'] : e['type'];
    return name is String ? name : '';
  }

  /// Does [name] mean a record, task or ticket changed?
  static bool isWork(String name) => _work.hasMatch(name);
}
