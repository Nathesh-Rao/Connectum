import 'dart:convert';

import 'package:flutter/services.dart';

import '../../data/models/ids.dart';
import '../../data/socket/socket_service.dart';

/// Debug only (`/debug/tickets`, see "Before release" in CLAUDE.md): the real
/// replies captured in `assets/debug/tickets/` answer the `status.*` calls in
/// place of the server, so Tickets can be tried with no connection.
class SeedTickets {
  SeedTickets._();

  static const _dir = 'assets/debug/tickets/';

  static bool isActive = false;
  static const me = 'ana';

  /// The next update fails with this error (stale, forbidden, ...).
  static SocketCallError? nextError;

  /// The next update is applied but its answer is lost (a timeout); the same
  /// request id sent again returns the first result.
  static bool isLosingNextAnswer = false;

  /// Every request id an update arrived with, newest last.
  static final requestIds = <String>[];

  static Map<String, dynamic> _structures = {};
  static List<Map<String, dynamic>> _tickets = [];
  static List<Map<String, dynamic>> _fixtureHistory = [];
  static final _extraHistory = <int, List<Map<String, dynamic>>>{};
  static final _answers = <String, Map<String, dynamic>>{};
  static int _seq = 100;

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  static Future<Map<String, dynamic>> _read(String name) async =>
      (jsonDecode(await rootBundle.loadString('$_dir$name')) as Map)
          .cast<String, dynamic>();

  static Future<void> start() async {
    final raised = (await _read('status_mine_raised.json'))['data'] as Map;
    final with_ = (await _read('status_mine_with.json'))['data'] as Map;
    final history = (await _read('status_history.json'))['data'] as Map;
    _structures = (raised['structures'] as Map).cast<String, dynamic>();
    _fixtureHistory = [
      for (final h in history['history'] as List) (h as Map).cast(),
    ];
    final base = ((with_['submissions'] as List).first as Map)
        .cast<String, dynamic>();
    _tickets = [
      _copy(base),
      _make(
        base,
        title: 'Printer jams on floor 2',
        by: me,
        values: {'assignee': 'ben', 'state': 'In progress', 'done': 30},
      ),
      _make(
        base,
        tstruct: 'help_task',
        title: 'Order new badges',
        by: me,
        values: {'assignee': 'ben', 'state': 'Forwarded', 'done': 0},
      ),
    ];
    _extraHistory.clear();
    _answers.clear();
    requestIds.clear();
    nextError = null;
    isLosingNextAnswer = false;
    isActive = true;
  }

  static void stop() {
    isActive = false;
    _tickets = [];
    nextError = null;
    isLosingNextAnswer = false;
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> t) =>
      (jsonDecode(jsonEncode(t)) as Map).cast<String, dynamic>();

  static Map<String, dynamic> _make(
    Map<String, dynamic> base, {
    required String title,
    required String by,
    String? tstruct,
    Map<String, dynamic> values = const {},
    String? status,
  }) {
    final t = _copy(base);
    t['id'] = ++_seq;
    t['by'] = by;
    t['ts'] = _now;
    if (tstruct != null) t['tstruct'] = tstruct;
    t['values'] = {
      ...(t['values'] as Map).cast<String, dynamic>(),
      'title': title,
      ...values,
    };
    if (status != null) {
      t['status'] = status;
      (t['values'] as Map).remove('state');
    }
    return t;
  }

  /// A ticket someone raised to me.
  static int addAssignedToMe() {
    final base = _tickets.first;
    final t = _make(
      base,
      title: 'Badge reader is offline',
      by: 'rhea',
      values: {'assignee': me, 'state': 'Open', 'done': 0},
    );
    _tickets.add(t);
    return t['id'] as int;
  }

  /// A ticket I raised that waits for approval.
  static int addAwaitingApproval() {
    final t = _make(
      _tickets.first,
      title: 'Visitor parking permit',
      by: me,
      values: {'assignee': 'ben', 'done': 0},
      status: 'pending',
    );
    _tickets.add(t);
    return t['id'] as int;
  }

  static String _tstructOf(Map<String, dynamic> t) => '${t['tstruct']}';

  static Map<String, dynamic> _statusOf(Map<String, dynamic> t) =>
      ((_structures[_tstructOf(t)] as Map)['status'] as Map)
          .cast<String, dynamic>();

  static String _assigneeOf(Map<String, dynamic> t) {
    final v = '${(t['values'] as Map)['assignee'] ?? ''}'.trim();
    return v.isEmpty ? '${t['by']}' : v;
  }

  static bool _isFinal(Map<String, dynamic> t) {
    final state = '${(t['values'] as Map)['state'] ?? ''}';
    for (final s in _statusOf(t)['statuses'] as List) {
      if ((s as Map)['name'] == state) return s['final'] == true;
    }
    return false;
  }

  static Map<String, dynamic> mine(String as, int offset, int limit) {
    final isWith = as == 'with';
    final rows = [
      for (final t in _tickets)
        if (!_isFinal(t) &&
            (isWith
                ? _assigneeOf(t) == me && t['status'] != 'pending'
                : '${t['by']}' == me))
          t,
    ];
    final page = rows.skip(offset).take(limit).toList();
    return {
      'hasMore': offset + page.length < rows.length && isWith,
      'structures': {
        for (final t in page) _tstructOf(t): _structures[_tstructOf(t)],
      },
      'submissions': page,
      'total': rows.length,
    };
  }

  static Map<String, dynamic> _find(int id) => _tickets.firstWhere(
    (t) => t['id'] == id,
    orElse: () => throw const SocketCallError('not_found', 'No such ticket.'),
  );

  static Map<String, dynamic> get(int id) {
    final t = _find(id);
    return {
      'inPool': false,
      'isAdmin': false,
      'structures': {_tstructOf(t): _structures[_tstructOf(t)]},
      'submission': t,
    };
  }

  static Map<String, dynamic> history(int id) {
    _find(id);
    return {
      'history': [..._fixtureHistory, ...?_extraHistory[id]],
    };
  }

  /// Applies an update the way the server would (state, holder, completion,
  /// one history record) and answers like `status.update`.
  static Map<String, dynamic> update(Map<String, dynamic> p) {
    final requestId = '${p['requestId']}';
    requestIds.add(requestId);
    final first = _answers[requestId];
    if (first != null) return {...first, 'repeated': true};
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    final id = idNumber(p['id']) ?? 0;
    final t = _find(id);
    final status = _statusOf(t);
    final action = (status['actions'] as List).cast<Map>().firstWhere(
      (a) => a['name'] == p['action'],
      orElse: () =>
          throw const SocketCallError('invalid', 'That action does not exist.'),
    );
    final values = (t['values'] as Map).cast<String, dynamic>();
    final from =
        '${values['state'] ?? (status['statuses'] as List).first['name']}';
    final holder = _assigneeOf(t);
    final next = switch (action['assign']) {
      'pick' => '${p['sendTo']}',
      'raiser' || 'previous' => '${t['by']}',
      'self' => me,
      _ => holder,
    };
    final completion = switch (action['percent']) {
      'hundred' => 100,
      'set' => intOf(p['percent']),
      _ => intOf(values['done']),
    };
    values['state'] = action['to'];
    values['assignee'] = next;
    values['done'] = completion;
    t.remove('status');
    final recordId = ++_seq;
    (_extraHistory[id] ??= []).add({
      'by': me,
      'id': recordId,
      'ts': _now,
      'values': {
        'Action': action['name'],
        'ByAdmin': 'No',
        'FromStatus': from,
        'ToStatus': action['to'],
        'Ticket': '$id',
        if ('${p['remarks'] ?? ''}'.isNotEmpty) 'Remarks': p['remarks'],
        if ('${p['reason'] ?? ''}'.isNotEmpty) 'Reason': p['reason'],
        if (action['percent'] != 'none') 'Percent': '$completion',
        if (action['assign'] == 'pick') 'SentTo': next,
      },
    });
    final answer = {
      'assignee': next,
      'byAdmin': false,
      'completion': completion,
      'record': recordId,
      'status': action['to'],
      'ticket': id,
    };
    _answers[requestId] = answer;
    if (isLosingNextAnswer) {
      isLosingNextAnswer = false;
      throw const SocketCallError('timeout');
    }
    return answer;
  }
}
