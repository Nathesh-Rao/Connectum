import '../../../data/records/record_commands.dart';

/// A `records.query` ask the client refuses before sending: it breaks a
/// limit the server states (`sd_recquery.erl`).
class InboxQueryError implements Exception {
  const InboxQueryError(this.message);

  final String message;

  @override
  String toString() => 'InboxQueryError($message)';
}

final _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// The arguments of `records.query` that the Inbox sends, as the filter
/// panel will fill them (Phase 3). Checked on the way out against the
/// server's limits; the server stays the judge of the rest.
class InboxQuery {
  const InboxQuery({
    this.scope = const [],
    this.forms = const [],
    this.createdBy = const [],
    this.sentBy = const [],
    this.sentTo = const [],
    this.taggedTo = const [],
    this.from = '',
    this.to = '',
    this.status = '',
    this.views = const [],
    this.groups = const [],
    this.isFacets = false,
  });

  /// `me` and/or `team`; empty is both (the server's default).
  final List<String> scope;
  final List<String> forms;
  final List<String> createdBy;
  final List<String> sentBy;
  final List<String> sentTo;
  final List<String> taggedTo;

  /// `YYYY-MM-DD` or ''.
  final String from;
  final String to;

  /// `open`, `closed` or ''.
  final String status;

  /// Each entry is one view object (`scope`, `createdBy`, `status`,
  /// `escalated`); a record is listed when any view holds it.
  final List<Map<String, dynamic>> views;

  /// The Advanced blocks as the server reads them (`groups`, at most 10).
  final List<Map<String, dynamic>> groups;

  /// Also ask what the panel's lists offer (`facets:true`): `formCounts` and
  /// `people`. Sent with limit 1, offset 0.
  final bool isFacets;

  /// The whole request. [limit] 1-200, [offset] 0-1,000,000. Throws
  /// [InboxQueryError] when something breaks a server limit.
  Map<String, dynamic> toArgs({
    int limit = RecordLimits.queryPageSize,
    int offset = 0,
  }) {
    if (limit < 1 || limit > RecordLimits.queryMaxLimit) {
      throw InboxQueryError(
        'limit must be 1-${RecordLimits.queryMaxLimit}, got $limit',
      );
    }
    if (offset < 0 || offset > RecordLimits.queryMaxOffset) {
      throw InboxQueryError('offset out of range: $offset');
    }
    for (final s in scope) {
      if (s != 'me' && s != 'team') {
        throw InboxQueryError('unknown scope "$s"');
      }
    }
    if (views.length > RecordLimits.queryMaxViews) {
      throw InboxQueryError(
        'at most ${RecordLimits.queryMaxViews} views, got ${views.length}',
      );
    }
    if (from.isNotEmpty && !_day.hasMatch(from)) {
      throw InboxQueryError('from must be YYYY-MM-DD');
    }
    if (to.isNotEmpty && !_day.hasMatch(to)) {
      throw InboxQueryError('to must be YYYY-MM-DD');
    }
    if (status.isNotEmpty && status != 'open' && status != 'closed') {
      throw InboxQueryError('status must be open or closed');
    }
    if (groups.length > RecordLimits.queryMaxGroups) {
      throw InboxQueryError(
        'at most ${RecordLimits.queryMaxGroups} groups, got ${groups.length}',
      );
    }
    final lists = {
      'forms': forms,
      'createdBy': createdBy,
      'sentBy': sentBy,
      'sentTo': sentTo,
      'taggedTo': taggedTo,
    };
    for (final e in lists.entries) {
      _checkNames(e.key, e.value);
    }
    return {
      if (scope.isNotEmpty) 'scope': scope,
      for (final e in lists.entries)
        if (e.value.isNotEmpty) e.key: e.value,
      if (from.isNotEmpty) 'from': from,
      if (to.isNotEmpty) 'to': to,
      if (status.isNotEmpty) 'status': status,
      // One view with nothing in it is every record: no `views` at all.
      if (views.isNotEmpty && !(views.length == 1 && views.first.isEmpty))
        'views': views,
      if (groups.isNotEmpty) 'groups': groups,
      if (isFacets) 'facets': true,
      'limit': limit,
      'offset': offset,
    };
  }

  static void _checkNames(String key, List<String> names) {
    if (names.length > RecordLimits.queryMaxNames) {
      throw InboxQueryError(
        '$key: at most ${RecordLimits.queryMaxNames} names, got ${names.length}',
      );
    }
    for (final n in names) {
      if (n.isEmpty || n.length > RecordLimits.queryMaxNameChars) {
        throw InboxQueryError(
          '$key: a name must be 1-${RecordLimits.queryMaxNameChars} characters',
        );
      }
    }
  }
}
