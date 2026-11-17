import 'dart:convert';
import 'dart:io';

import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/smart_view/models/sv_source.dart';

import '../support/fake_socket.dart';

/// A real capture of the BE (`test/fixtures/smart_view/real/<number>-*.json`).
Map<String, dynamic> capture(String number) {
  final dir = Directory('test/fixtures/smart_view/real');
  final file = dir.listSync().whereType<File>().firstWhere(
    (f) => f.uri.pathSegments.last.startsWith('$number-'),
  );
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();
}

/// The `data` of a capture's reply.
Map<String, dynamic> captured(String number) =>
    ((capture(number)['reply'] as Map)['data'] as Map).cast<String, dynamic>();

/// The source list of capture `004-` (the author's): hidden fields are not in
/// it.
List<SvSource> realSources() => [
  for (final f in captured('004')['forms'] as List) ?SvSource.tryParse(f),
];

SvSource sourceNamed(String name) =>
    realSources().firstWhere((s) => s.name == name);

/// Virtual time: a delay moves the clock and returns at once, so a test of a
/// 10-second window takes no real time.
class VClock {
  DateTime now = DateTime(2026, 11, 16, 12);
  final waits = <Duration>[];

  DateTime read() => now;

  Future<void> delay(Duration d) async {
    waits.add(d);
    now = now.add(d);
    await Future<void>.delayed(Duration.zero);
  }
}

class SvRig {
  SvRig({String user = 'svcapcpw1ann'}) {
    store = FakeStore(user: user);
    socket = FakeSocket()..goOnline();
    tickets = TicketRepository(socket, store, FakeConversations());
    repo = SmartViewRepository(
      socket,
      store,
      tickets,
      now: clock.read,
      delay: clock.delay,
    )..onInit();
  }

  final clock = VClock();
  late final FakeStore store;
  late final FakeSocket socket;
  late final TicketRepository tickets;
  late final SmartViewRepository repo;

  /// Commands sent at or after [from] within [window].
  int count(String action) => socket.count(action);
}

/// A row in the shape of a `submissions.list` row.
Map<String, dynamic> ownRow(
  int id, {
  String tstruct = 'tickets',
  int? ts,
  Map<String, dynamic>? values,
  bool canEdit = true,
}) => {
  'branch': 'HQ',
  'by': 'svcapcpw1ann',
  'byName': 'Ann Rao',
  'canEdit': canEdit,
  'files': <String, dynamic>{},
  'host': null,
  'id': id,
  'labels': <String, dynamic>{},
  'scope': 'user',
  'ts': ts ?? 1000000 + id,
  'tstruct': tstruct,
  'values': values ?? {'title': 'Row $id', 'stage': 'Open'},
};

/// A row in the shape of a `records.mine` row (no `canEdit`, `byName`,
/// `labels`, `files`).
Map<String, dynamic> mineRow(
  int id, {
  String tstruct = 'tickets',
  int? ts,
  Map<String, dynamic>? values,
}) => {
  'actedBy': 'svcapcpw1bob',
  'actionSeq': 1,
  'assignor': 'svcapcpw1bob',
  'branch': 'HQ',
  'by': 'svcapcpw1bob',
  'editedTs': 5,
  'holder': 'svcapcpw1ann',
  'host': null,
  'id': id,
  'participants': ['svcapcpw1ann', 'svcapcpw1bob'],
  'scope': 'global',
  'ts': ts ?? 1000000 + id,
  'tstruct': tstruct,
  'values': values ?? {'title': 'Received $id', 'stage': 'Open'},
};

/// An answer function that pages [rows] like `submissions.list`: [pageSize]
/// per page at most, `hasMore` while rows are left.
Map<String, dynamic> Function(Map<String, dynamic>) listPager(
  List<Map<String, dynamic>> rows, {
  int pageSize = 500,
}) => (args) {
  final offset = (args['offset'] as int?) ?? 0;
  final limit = ((args['limit'] as int?) ?? pageSize).clamp(1, pageSize);
  final page = rows.skip(offset).take(limit).toList();
  return {
    'submissions': page,
    'total': rows.length,
    'offset': offset,
    'limit': limit,
    'hasMore': offset + page.length < rows.length,
  };
};

/// Pages `records.mine` like the server: at most [pageSize] rows a page
/// whatever `limit` says, `next` always null, `hasMore` while rows are left.
Map<String, dynamic> Function(Map<String, dynamic>) minePager(
  Map<String, List<Map<String, dynamic>>> byAs, {
  int pageSize = 2,
}) => (args) {
  final rows = byAs['${args['as']}'] ?? const [];
  final offset = (args['offset'] as int?) ?? 0;
  final page = rows.skip(offset).take(pageSize).toList();
  return {
    'submissions': page,
    'structures': <String, dynamic>{},
    'total': rows.length,
    'hasMore': offset + page.length < rows.length,
    'next': null,
  };
};
