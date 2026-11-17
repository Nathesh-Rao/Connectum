import '../records/record_commands.dart';

/// The `sd` command names Smart View reads with: the only place they are
/// written. The server does not know `#view`; nothing here is sent for it.
class SvCmd {
  SvCmd._();

  /// The source list (`{what:'forms'}`); hidden fields are left out of it.
  static const sources = 'ai.enterprise';
  static const rows = 'submissions.list';
  static const mine = RecordCmd.mine;
  static const one = RecordCmd.get;
}

class SvEvents {
  SvEvents._();

  static const changed = 'submissions_changed';
  static const approved = 'submission_approved';
  static const rejected = 'submission_rejected';
  static const assigned = 'ticket_assigned';
  static const structures = 'tstructs_changed';
  static const resync = 'resync';

  /// The events that mean "a record of a structure changed".
  static const record = {changed, approved, rejected, assigned};
}

class SvLimits {
  SvLimits._();

  /// `submissions.list`: 500 a page, at most 20 pages (10,000 records).
  static const rowsPageSize = 500;
  static const rowsMaxPages = 20;

  /// `records.mine` with and involved: 200 a page, at most 3 pages each.
  static const mineMaxPages = 3;

  /// Between two page reads.
  static const gap = Duration(milliseconds: 300);

  /// The source list is read once per open and kept this long.
  static const sourcesTtl = Duration(seconds: 60);

  /// Smart View never sends more than this many commands in [window].
  static const budget = 6;
  static const window = Duration(seconds: 10);

  /// Events are collected this long, then one refresh runs.
  static const eventDebounce = Duration(milliseconds: 600);

  /// A source list answers at most this many suggestions.
  static const maxSuggestions = 30;

  /// `rate_limited` / `busy`: wait 1, 2, 3, 4 s, then give up.
  static const maxRetries = 4;
  static const retryable = {'rate_limited', 'busy'};
}
