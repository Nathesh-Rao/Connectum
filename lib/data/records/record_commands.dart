/// The `sd` command names of the record flow and of tasks: the only place
/// they are written. Record commands are WebSocket only (`/sd <action> {json}`);
/// there is no HTTP route for them.
class RecordCmd {
  RecordCmd._();

  static const mine = 'records.mine';
  static const get = 'submission.get';
  static const history = 'submission.history';
  static const actions = 'record.actions';
  static const summary = 'records.summary';
  static const status = 'record.status';
  static const send = 'record.send';
  static const targets = 'record.targets';
  static const people = 'record.people';
  static const thread = 'record.thread';

  /// The Inbox's reads: the server runs the filter (`records.query`), counts
  /// per view, the people the filter offers (`records.people`) and the
  /// name/designation/picture of user names (`people.cards`).
  static const query = 'records.query';
  static const counts = 'records.counts';
  static const queryPeople = 'records.people';
  static const peopleCards = 'people.cards';

  /// The Inbox's saved views (`sd_inboxview.erl`).
  static const viewsGet = 'inbox.views.get';
  static const viewsSave = 'inbox.views.save';
  static const viewsDelete = 'inbox.views.delete';
  static const viewsDefault = 'inbox.views.default';

  static const submit = 'tstruct.submit';
  static const userSubmit = 'tstruct.user.submit';
  static const openStructure = 'tstruct.user.open';
  static const update = 'submissions.update';
  static const resubmit = 'submission.resubmit';
  static const delete = 'submissions.delete';
  static const list = 'submissions.list';

  /// Removed on the server (`unknown_action`, no alias). Kept only so a scan
  /// test can prove nothing sends them; never used to build a request.
  static const removed = [
    'status.mine',
    'status.get',
    'status.update',
    'status.history',
    'task.fetch',
  ];
}

class TaskCmd {
  TaskCmd._();

  static const create = 'task.create';
  static const get = 'task.get';
  static const list = 'task.list';
  static const update = 'task.update';
  static const send = 'task.send';
}

/// The live events the record flow and tasks listen to.
class RecordEvents {
  RecordEvents._();

  static const changed = 'submissions_changed';
  static const assigned = 'ticket_assigned';
  static const feedItem = 'feed_item';
  static const formMessage = 'form_message';
  static const formMessageUpdated = 'form_message_updated';
  static const taskAssigned = 'task_assigned';
  static const taskUpdated = 'task_updated';
}

/// Limits the server states for record files (not the chat `/upload` ones).
class RecordLimits {
  RecordLimits._();

  /// 10 MB per file on dev (`CONNECTUM_MAX_FILE_MB`); the server stays the
  /// judge.
  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxFiles = 10;
  static const maxText = 1000;
  static const maxRequestIdBytes = 100;
  static const maxHours = 24;

  /// The server clamps a `records.mine` limit to 1-200.
  static const mineMaxLimit = 200;

  /// The `limit` every `records.mine` call sends. `raised` always asks for 200:
  /// the server drops records when the limit is smaller than the kept records
  /// of its 200-entry chunk and then answers `hasMore:false` (found by the BE,
  /// 16 Nov 2026), so no smaller limit is ever sent for it. The other lists
  /// use [requested] within 1-200.
  static int mineLimit(String as, int requested) =>
      as == 'raised' ? mineMaxLimit : requested.clamp(1, mineMaxLimit);

  /// `records.query` (`sd_recquery.erl`): limit 1-200, people names at most 50
  /// of at most 200 characters, at most 8 views. The page the Inbox asks.
  static const queryMaxLimit = 200;
  static const queryPageSize = 100;
  static const queryMaxNames = 50;
  static const queryMaxNameChars = 200;
  static const queryMaxViews = 8;
  static const queryMaxGroups = 10;
  static const queryMaxOffset = 1000000;

  /// `people.cards`: at most this many user names in one call.
  static const peopleCardsBatch = 60;
}
