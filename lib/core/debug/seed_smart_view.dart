import 'dart:async';

import '../../data/models/ids.dart';
import '../../data/smart_view/models/sv_row.dart';
import '../../data/smart_view/models/sv_source.dart';
import '../../data/smart_view/smart_view_commands.dart';
import '../../data/socket/socket_service.dart';
import 'seed_tickets.dart';

/// Debug and demo only (`/debug/smartview`, `DEMO_MODE`; see "Before release"
/// in CLAUDE.md): an in-memory server for Smart View. Four structures: Leave
/// request (120 records: 70 of mine through `submissions.list`, 30 with me and
/// 20 involved through `records.mine`, 20 of mine also with me), Expense claim
/// (empty), Ticket (`not_found`) and Work order (fails once, then answers).
/// Records live in [SeedTickets], so a tap opens the real record screen. The
/// Leave request has a hidden field (`internal_note`): it is in every row and
/// in no field list.
class SeedSmartView {
  SeedSmartView._();

  static bool isActive = false;
  static const me = SeedTickets.me;

  /// Where the fake server's live events go; null: nobody listens.
  static void Function(Map<String, dynamic> event)? emit;

  /// Events carry `data.record` (a server with #822) or not (a release).
  static bool isRecordMode = false;

  static const leave = 'leave';
  static const hiddenValue = 'HIDDEN-DEMO-NOTE';

  static bool _isFlakyDone = false;
  static Timer? _changeTimer;
  static Timer? _newTimer;
  static int? _changeId;

  static const _leaveForm = {
    'caption': 'Leave request',
    'fields': {
      'title': 'Reason',
      'from': 'From',
      'days': 'Days',
      'kind': 'Leave type',
      'stage': 'Stage',
      'to': 'To',
      'start_time': 'Start time',
      'balance': 'Balance (days)',
      'manager': 'Manager',
      'notes': 'Notes',
      'covered': 'Cover arranged',
    },
    'recordThread': false,
    'status': {
      'field': 'stage',
      'statuses': ['Open', 'In progress', 'On hold', 'Blocked', 'Done'],
      'final': ['Done'],
    },
  };

  /// A date spread over six months (Sep 2026 to Feb 2027).
  static String _day(int i, int plus) {
    final d = DateTime(2026, 9 + i * 7 % 6, i % 27 + 1 + plus);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static Map<String, dynamic> leaveValues(int i) {
    const kinds = ['Annual', 'Sick', 'Casual', 'Unpaid'];
    return {
      'title': 'Leave ${(i + 1).toString().padLeft(3, '0')}',
      'stage': i % 7 == 0
          ? 'Done'
          : i % 11 == 0
          ? 'Blocked'
          : i % 13 == 0
          ? 'On hold'
          : (i % 3 == 0 ? 'In progress' : 'Open'),
      'from': i % 17 == 0 ? '' : _day(i, 0),
      'days': i % 10 == 3 ? null : i % 5 + 1,
      'kind': kinds[i % 4],
      'to': i % 17 == 0 ? '' : _day(i, 1),
      'start_time': i % 4 == 0 ? '' : '0${9 + i % 3}:30',
      'balance': i % 8 == 5 ? null : 24 - i % 9,
      'manager': i % 6 == 0 ? '' : 'Rhea Kapoor',
      'notes': i % 5 == 0
          ? 'Travelling to attend a family wedding out of town and then '
                'staying on for a few days to look after my parents; I '
                'will be reachable by phone for anything urgent and my '
                'tasks are handed over to the team before I go.'
          : i % 5 == 1
          ? ''
          : 'Short note',
      'covered': i % 2 == 0,
      'internal_note': hiddenValue,
    };
  }

  /// The Leave request source and rows without any server (the table lab).
  static SvSource leaveSource() =>
      SvSource.tryParse((_sources()['forms'] as List).first)!;

  static List<SvRow> leaveRows([int count = 120]) {
    final t = DateTime.now().millisecondsSinceEpoch;
    return [
      for (var i = 0; i < count; i++)
        SvRow(
          id: 1000 + i,
          tstruct: leave,
          by: me,
          byName: 'Ana Rao',
          ts: t - 60000 * (i + 1),
          recordStatus: i % 9 == 0
              ? 'pending'
              : i % 11 == 0
              ? 'rejected'
              : i % 4 == 0
              ? 'approved'
              : '',
          values: leaveValues(i),
        ),
    ];
  }

  static Future<void> start({bool isLive = true}) async {
    stop();
    _isFlakyDone = false;
    SeedTickets.addDemoForm(leave, _leaveForm);
    final t = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 120; i++) {
      final ts = t - 60000 * (i + 1);
      final values = leaveValues(i);
      if (i < 70) {
        // Mine. The first 20 are with me too (the merge keeps one copy).
        SeedTickets.addDemoRecord(
          leave,
          values,
          by: me,
          holder: i < 20 ? me : 'sam',
          ts: ts,
          completion: i % 3 == 0 ? 40 : 0,
        );
      } else if (i < 100) {
        SeedTickets.addDemoRecord(
          leave,
          {...values, 'stage': i % 2 == 0 ? 'Open' : 'In progress'},
          by: 'rhea',
          holder: me,
          ts: ts,
        );
      } else {
        SeedTickets.addDemoRecord(
          leave,
          {...values, 'stage': 'Open'},
          by: 'rhea',
          holder: 'sam',
          participants: [me],
          ts: ts,
        );
      }
    }
    isActive = true;
    if (isLive) startLive();
  }

  static void stop() {
    _changeTimer?.cancel();
    _newTimer?.cancel();
    _changeTimer = _newTimer = null;
    isActive = false;
  }

  /// After 10 s a record of mine changes status, after 20 s a new one
  /// appears.
  static void startLive({
    Duration changeAfter = const Duration(seconds: 10),
    Duration newAfter = const Duration(seconds: 20),
  }) {
    _changeTimer?.cancel();
    _newTimer?.cancel();
    _changeTimer = Timer(changeAfter, changeStatus);
    _newTimer = Timer(newAfter, addRecord);
  }

  static Map<String, dynamic> _recordOf(Map<String, dynamic> r) => {
    'by': r['by'],
    'claimants': <String>[],
    'completion': r['completion'],
    'final': ((r['values'] as Map)['stage']) == 'Done',
    'holder': r['holder'],
    'status': (r['values'] as Map)['stage'],
    'ts': r['editedTs'] ?? r['ts'],
  };

  static void _emit(String event, Map<String, dynamic> data) =>
      emit?.call({'type': 'sd_event', 'event': event, 'data': data});

  /// Another person moves record [id] (the newest of mine by default).
  static void changeStatus({int? id}) {
    if (!isActive) return;
    final mine = _own();
    if (mine.isEmpty) return;
    final target = id ?? _changeId ?? intOf(mine.first['id']);
    _changeId = target;
    final r = SeedTickets.setDemoStatus(target, 'In progress');
    if (r == null) return;
    _emit(SvEvents.changed, {
      'id': target,
      'tstruct': leave,
      'action': 'Status update',
      'by': 'sam',
      if (isRecordMode) 'record': _recordOf(r),
    });
  }

  /// A new record of mine appears.
  static int addRecord() {
    if (!isActive) return 0;
    final id = SeedTickets.addDemoRecord(
      leave,
      {
        'title': 'Leave new',
        'stage': 'Open',
        'from': '2026-12-30',
        'days': 2,
        'kind': 'Annual',
        'internal_note': hiddenValue,
      },
      by: me,
      holder: me,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    final r = SeedTickets.recordsOf(leave).firstWhere((x) => x['id'] == id);
    _emit(SvEvents.changed, {
      'id': id,
      'tstruct': leave,
      'action': 'created',
      'by': me,
      if (isRecordMode) 'record': _recordOf(r),
    });
    return id;
  }

  static List<Map<String, dynamic>> _own() => [
    for (final r in SeedTickets.recordsOf(leave))
      if (r['by'] == me) r,
  ]..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));

  static Map<String, dynamic> _field(String n, String c, String type) => {
    'name': n,
    'caption': c,
    'type': type,
    'section': null,
  };

  static Map<String, dynamic> _ticketSource(
    String name,
    String caption,
    List<String> statuses,
    String last, {
    bool hasThread = false,
  }) => {
    'name': name,
    'caption': caption,
    'keyField': 'title',
    'owner': 'rhea',
    'system': true,
    'canFetch': true,
    'canAdd': false,
    'recordThread': hasThread,
    'fromSheet': false,
    'status': {
      'field': 'stage',
      'statuses': statuses,
      'final': [last],
    },
    'fields': [
      _field('title', 'Title', 'text'),
      _field('stage', 'Stage', 'selection'),
    ],
    'sections': <Object>[],
  };

  static Map<String, dynamic> _sources() => {
    'forms': [
      {
        'name': leave,
        'caption': 'Leave request',
        'keyField': 'title',
        'owner': me,
        'system': false,
        'canFetch': true,
        'canAdd': true,
        'recordThread': false,
        'fromSheet': false,
        'status': _leaveForm['status'],
        'fields': [
          _field('title', 'Reason', 'text'),
          _field('from', 'From', 'date'),
          _field('days', 'Days', 'number'),
          _field('kind', 'Leave type', 'selection'),
          _field('stage', 'Stage', 'selection'),
          _field('to', 'To', 'date'),
          _field('start_time', 'Start time', 'time'),
          _field('balance', 'Balance (days)', 'number'),
          _field('manager', 'Manager', 'text'),
          _field('notes', 'Notes', 'text'),
          _field('covered', 'Cover arranged', 'toggle'),
        ],
        'sections': <Object>[],
      },
      {
        'name': 'expense',
        'caption': 'Expense claim',
        'keyField': null,
        'owner': me,
        'system': false,
        'canFetch': true,
        'canAdd': true,
        'recordThread': false,
        'fromSheet': false,
        'status': null,
        'fields': [
          _field('title', 'Title', 'text'),
          _field('amount', 'Amount', 'number'),
        ],
        'sections': <Object>[],
      },
      _ticketSource(
        'help_ticket',
        'Ticket',
        const ['Open', 'In progress', 'Done'],
        'Done',
        hasThread: true,
      ),
      _ticketSource('help_task', 'Work order', const [
        'New',
        'Working',
        'Closed',
      ], 'Closed'),
    ],
  };

  static Map<String, dynamic> _ownRows(Map<String, dynamic> args) {
    final name = '${args['tstruct']}';
    final offset = intOf(args['offset']).clamp(0, 1 << 30);
    final limit = intOf(args['limit']).clamp(1, 500);
    final all = [
      for (final r in SeedTickets.recordsOf(name))
        if (r['by'] == me) r,
    ]..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
    final page = all.skip(offset).take(limit).toList();
    return {
      'submissions': [
        for (final r in page)
          {
            'id': r['id'],
            'tstruct': name,
            'by': r['by'],
            'byName': 'Ana Rao',
            'ts': r['ts'],
            'holder': r['holder'],
            'completion': r['completion'],
            'canEdit': true,
            'labels': <String, dynamic>{},
            'files': <String, dynamic>{},
            'scope': 'user',
            'values': r['values'],
          },
      ],
      'total': all.length,
      'offset': offset,
      'limit': limit,
      'hasMore': offset + page.length < all.length,
    };
  }

  static Future<Map<String, dynamic>> answer(
    String cmd,
    Map<String, dynamic> args,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    switch (cmd) {
      case SvCmd.sources:
        return _sources();
      case SvCmd.rows:
        final name = '${args['tstruct']}';
        if (name == 'help_ticket') {
          throw const SocketCallError('not_found', 'No such structure.');
        }
        if (name == 'help_task' && !_isFlakyDone) {
          _isFlakyDone = true;
          throw const SocketCallError(
            'error',
            'Something went wrong on the server.',
          );
        }
        return _ownRows(args);
      case SvCmd.mine:
      case SvCmd.one:
        return SeedTickets.answer(cmd, args);
    }
    throw SocketCallError('unknown_action', 'Unknown sd action: $cmd');
  }
}
