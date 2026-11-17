import 'dart:async';

import '../../data/models/ids.dart';
import '../../data/records/record_commands.dart';
import '../../data/socket/socket_service.dart';

/// Debug and demo only (`/debug/tickets`, `DEMO_MODE`; see "Before release" in
/// CLAUDE.md): an in-memory server for the record flow. It answers the
/// `records.*`, `record.*` and `submission.*` calls in the shapes captured in
/// `tools/postman/examples.json`, so tickets work with no connection.
///
/// Records: with me (open, in progress, one that needs a comment, 70 sample
/// rows so `hasMore` pages with short pages), raised by me (one with someone
/// else, one final, one waiting for approval) and involved.
class SeedTickets {
  SeedTickets._();

  static bool isActive = false;
  static const me = 'ana';

  /// The next write fails with this error (stale, forbidden, busy, ...).
  static SocketCallError? nextError;

  /// The next write is applied but its answer is lost; the same request id
  /// sent again returns the first result with `repeated: true`.
  static bool isLosingNextAnswer = false;

  /// Every request id a write arrived with, newest last.
  static final requestIds = <String>[];

  /// Where the fake server's live events go (the record repository listens in
  /// the demo). Null: nobody listens.
  static void Function(Map<String, dynamic> event)? emit;

  static Timer? _statusTimer;
  static Timer? _assignTimer;

  /// The demo's other person: after a few seconds `sam` moves a record that is
  /// with me to the next status (an event only says it changed), and a little
  /// later `rhea` sends me a new one (`ticket_assigned`). Demo builds only.
  static void startOtherPerson({
    Duration statusAfter = const Duration(seconds: 12),
    Duration assignAfter = const Duration(seconds: 24),
  }) {
    _statusTimer?.cancel();
    _assignTimer?.cancel();
    _statusTimer = Timer(statusAfter, otherUpdatesStatus);
    _assignTimer = Timer(assignAfter, otherSendsRecord);
  }

  /// `sam` updates the status of record [id] (31 by default, which is with me).
  static void otherUpdatesStatus({int id = 31}) {
    if (!isActive) return;
    final r = _find(id);
    final statuses = (_spec(r)['statuses'] as List).cast<String>();
    final from = _statusOf(r);
    final next = statuses[(statuses.indexOf(from) + 1) % statuses.length];
    (r['values'] as Map)['stage'] = next;
    r['editedTs'] = _now;
    _log(
      id,
      'status',
      by: 'sam',
      extra: {
        'fromStatus': from,
        'toStatus': next,
        'completion': '${r['completion']}',
        'remarks': 'Looking at it now.',
        'final': (_spec(r)['final'] as List).contains(next),
        'files': <String>[],
        'asAdmin': false,
      },
    );
    _emit('submissions_changed', {
      'id': id,
      'tstruct': r['tstruct'],
      'action': 'Status update',
    });
  }

  /// `rhea` sends me a new record: `submissions_changed` and `ticket_assigned`.
  static int otherSendsRecord() {
    final id = addAssignedToMe();
    final r = _find(id);
    _emit('ticket_assigned', {
      'id': id,
      'tstruct': r['tstruct'],
      'action': 'Send',
      'by': 'rhea',
    });
    _emit('submissions_changed', {
      'id': id,
      'tstruct': r['tstruct'],
      'action': 'Send',
    });
    return id;
  }

  static void _emit(String event, Map<String, dynamic> data) {
    emit?.call({'type': 'sd_event', 'event': event, 'data': data});
  }

  /// A page never holds more than this, whatever `limit` says.
  static const pageCap = 60;

  /// The entries the server reads at once for `raised`.
  static const raisedChunk = 200;

  /// Records where the demo user is an administrator.
  static const _adminIds = {34};

  /// Demo records for the card bars (chat `dm:forms` and the Work Space):
  /// what `record.actions` returns differs per record.
  static const demoBoth = 61;
  static const demoNoSend = 62;
  static const demoNoStatus = 63;
  static const demoSendOff = 64;
  static const demoNotFound = 65;

  /// Demo records for the History panel: every kind of event, 40 events, 2.
  static const demoHistoryAll = 71;
  static const demoHistoryLong = 72;
  static const demoHistoryShort = 73;

  static const people = {
    'ana': ('Ana Rao', 'Analyst'),
    'ben': ('Ben Iyer', 'Technician'),
    'rhea': ('Rhea Das', 'Manager'),
    'sam': ('Sam Joseph', 'Technician'),
  };

  static const _forms = {
    'help_ticket': {
      'caption': 'Ticket',
      'fields': {'stage': 'Stage', 'title': 'Title'},
      'recordThread': true,
      'status': {
        'field': 'stage',
        'statuses': ['Open', 'In progress', 'Done'],
        'final': ['Done'],
      },
    },
    'help_task': {
      'caption': 'Work order',
      'fields': {'stage': 'Stage', 'title': 'Title'},
      'recordThread': false,
      'status': {
        'field': 'stage',
        'statuses': ['New', 'Working', 'Closed'],
        'final': ['Closed'],
      },
    },
  };

  static List<Map<String, dynamic>> _records = [];
  static final _events = <int, List<Map<String, dynamic>>>{};
  static final _answers = <String, Map<String, dynamic>>{};
  static int _seq = 100;
  static int _eventSeq = 1000;

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  static Future<void> start() async {
    _extraForms.clear();
    _demoSeq = 1000;
    _records = [];
    _events.clear();
    _answers.clear();
    requestIds.clear();
    nextError = null;
    isLosingNextAnswer = false;
    _seq = 100;
    final t = _now;
    _add(31, 'Printer is jammed', 'Open', by: 'rhea', holder: me, ts: t - 9e6);
    _add(
      32,
      'Badge reader down',
      'In progress',
      by: 'rhea',
      holder: me,
      completion: 40,
      ts: t - 8e6,
    );
    _add(
      34,
      'Admin sample: lower the completion',
      'In progress',
      by: 'rhea',
      holder: me,
      completion: 60,
      ts: t - 7.5e6,
    );
    _add(
      33,
      'Order new chairs',
      'New',
      by: 'sam',
      holder: me,
      tstruct: 'help_task',
      ts: t - 7e6,
    );
    _add(
      41,
      'Wi-Fi drops on floor 2',
      'In progress',
      by: me,
      holder: 'ben',
      assignor: me,
      completion: 30,
      ts: t - 6e6,
    );
    _add(
      42,
      'Replace toner',
      'Done',
      by: me,
      holder: 'ben',
      assignor: me,
      completion: 100,
      ts: t - 5e6,
    );
    _add(
      43,
      'New laptop request',
      'Open',
      by: me,
      holder: me,
      pending: true,
      ts: t - 4e6,
    );
    _add(
      51,
      'Keys for the store room',
      'Open',
      by: 'rhea',
      holder: 'sam',
      assignor: me,
      ts: t - 3e6,
    );
    for (final (id, title) in const [
      (demoBoth, 'Demo: Send and Update status'),
      (demoNoSend, 'Demo: no Send on this form'),
      (demoNoStatus, 'Demo: no status field'),
      (demoSendOff, 'Demo: Send is off'),
      (demoNotFound, 'Demo: record.actions not found'),
      (demoHistoryAll, 'Demo: history with every event'),
      (demoHistoryLong, 'Demo: history of 40 events'),
      (demoHistoryShort, 'Demo: history of 2 events'),
    ]) {
      _add(id, title, 'Open', by: 'rhea', holder: me, ts: t - 2e6 - id * 100);
    }
    for (var i = 0; i < 70; i++) {
      _add(
        200 + i,
        'Sample request ${i + 1}',
        'Open',
        by: 'rhea',
        holder: me,
        ts: t - 1e6 - i * 1000,
      );
    }
    for (final r in _records) {
      _log(r['id'] as int, 'created', by: '${r['by']}');
    }
    _log(
      41,
      'sent',
      by: me,
      extra: {
        'to': ['ben'],
        'via': 'user',
        'fromHolder': me,
        'reason': 'Needs the technician',
        'status': 'Open',
        'files': <String>[],
        'asAdmin': false,
      },
    );
    _log(
      41,
      'status',
      by: 'ben',
      extra: {
        'fromStatus': 'Open',
        'toStatus': 'In progress',
        'completion': '30',
        'remarks': 'Technician called',
        'final': false,
        'files': <String>[],
        'asAdmin': false,
      },
    );
    _log(
      42,
      'status',
      by: 'ben',
      extra: {
        'fromStatus': 'In progress',
        'toStatus': 'Done',
        'completion': '100',
        'final': true,
        'files': <String>[],
        'asAdmin': false,
      },
    );
    _demoHistories();
    isActive = true;
  }

  /// Three records with a hand-made history, oldest first, a minute apart.
  static void _demoHistories() {
    final end = _now;
    void log(int id, int n, int total, String op, Map<String, dynamic> extra) {
      _log(
        id,
        op,
        by: extra.remove('by') as String? ?? me,
        extra: {'ts': end - (total - n) * 60000 * 7, ...extra},
      );
    }

    Map<String, dynamic> status(
      String from,
      String to,
      String percent, {
      bool isFinal = false,
      String? remarks,
      String? hours,
      List<String> files = const [],
    }) => {
      'by': 'ben',
      'fromStatus': from,
      'toStatus': to,
      'completion': percent,
      'final': isFinal,
      'files': files,
      'asAdmin': false,
      ?(remarks == null ? null : 'remarks'): remarks,
      ?(hours == null ? null : 'hours'): hours,
    };

    const long =
        'Technician called the vendor, who confirmed the part is on back '
        'order. A temporary unit was fitted on the second floor and the '
        'original will be swapped as soon as the delivery arrives next week. '
        'Please do not close this until then.';
    _events[demoHistoryAll] = [];
    final all = <(String, Map<String, dynamic>)>[
      ('created', {'by': 'rhea'}),
      (
        'edited',
        {
          'by': 'rhea',
          'changes': [
            {'field': 'title', 'from': 'Printer', 'to': 'Printer is jammed'},
            {'field': 'stage', 'from': 'New', 'to': 'Open'},
            {'field': 'title', 'from': 'a', 'to': 'b'},
            {'field': 'stage', 'from': 'c', 'to': 'd'},
          ],
        },
      ),
      ('sent_for_approval', {'by': 'rhea'}),
      ('waiting', {'by': 'rhea'}),
      ('declined', {'by': 'sam', 'reason': 'Needs a cost estimate first'}),
      ('returned', {'by': 'sam', 'remarks': 'Back to you with a question.'}),
      ('resubmitted', {'by': 'rhea'}),
      ('approved', {'by': 'sam'}),
      ('approved_final', {'by': 'sam'}),
      (
        'sent',
        {
          'by': me,
          'to': ['ben'],
          'via': 'user',
          'fromHolder': me,
          'reason': 'Needs the technician',
          'status': 'Open',
        },
      ),
      (
        'sent',
        {
          'by': me,
          'to': ['ben', 'sam', 'rhea'],
          'via': 'auto',
          'fromHolder': me,
          'status': 'Open',
        },
      ),
      (
        'reassigned',
        {
          'by': 'rhea',
          'to': ['sam'],
          'asAdmin': true,
        },
      ),
      (
        'status',
        status(
          'Open',
          'In progress',
          '30',
          remarks: 'Technician called',
          hours: '2.5',
        ),
      ),
      ('status', status('In progress', 'In progress', '81', remarks: long)),
      ('status', status('In progress', 'Done', '100', isFinal: true)),
      ('deleted', {'by': 'rhea'}),
      ('archived_elsewhere', {'by': 'ben'}),
    ];
    for (var i = 0; i < all.length; i++) {
      log(demoHistoryAll, i, all.length, all[i].$1, {...all[i].$2});
    }

    _events[demoHistoryLong] = [];
    for (var i = 0; i < 40; i++) {
      final isSend = i % 3 == 1;
      log(
        demoHistoryLong,
        i,
        40,
        i == 0
            ? 'created'
            : isSend
            ? 'sent'
            : 'status',
        i == 0
            ? {'by': 'rhea'}
            : isSend
            ? {
                'by': me,
                'to': [i % 2 == 0 ? 'ben' : 'sam'],
                'fromHolder': me,
                'via': 'user',
              }
            : status('Open', 'In progress', '${(i * 2).clamp(0, 99)}'),
      );
    }

    _events[demoHistoryShort] = [];
    log(demoHistoryShort, 0, 2, 'created', {'by': 'rhea'});
    log(demoHistoryShort, 1, 2, 'sent', {
      'by': 'rhea',
      'to': [me],
      'fromHolder': 'rhea',
      'via': 'user',
    });
  }

  static void stop() {
    isActive = false;
    _statusTimer?.cancel();
    _assignTimer?.cancel();
    _statusTimer = null;
    _assignTimer = null;
    _records = [];
    _extraForms.clear();
    nextError = null;
    isLosingNextAnswer = false;
  }

  static void _add(
    int id,
    String title,
    String status, {
    required String by,
    required String holder,
    String assignor = '',
    int completion = 0,
    String tstruct = 'help_ticket',
    bool pending = false,
    required num ts,
  }) {
    _records.add({
      'id': id,
      'tstruct': tstruct,
      'by': by,
      'holder': holder,
      'assignor': assignor,
      'completion': completion,
      'hours': null,
      'ts': ts.toInt(),
      'editedTs': ts.toInt(),
      'branch': 'HQ',
      'scope': 'global',
      'host': null,
      'participants': {by, holder, if (assignor.isNotEmpty) assignor}.toList(),
      if (pending) 'status': 'pending',
      'values': {'title': title, 'stage': status},
    });
  }

  /// Forms the fake record server knows (its status tables).
  static bool handles(String tstruct) =>
      _forms.containsKey(tstruct) || _extraForms.containsKey(tstruct);

  /// Ids of Smart View's demo records: clear of the sample rows (200 to 269).
  static int _demoSeq = 1000;

  /// Forms other fake servers add (Smart View's demo structures).
  static final _extraForms = <String, Map<String, dynamic>>{};

  static Map<String, dynamic>? _formOf(String tstruct) =>
      _forms[tstruct] ?? _extraForms[tstruct];

  /// Smart View's demo: a structure with a status table whose records the
  /// record screens can open. Cleared by [start] and [stop].
  static void addDemoForm(String name, Map<String, dynamic> form) =>
      _extraForms[name] = form;

  /// Smart View's demo: one record of a demo form; returns its id.
  static int addDemoRecord(
    String tstruct,
    Map<String, dynamic> values, {
    required String by,
    required String holder,
    int completion = 0,
    List<String> participants = const [],
    required int ts,
  }) {
    final id = _demoSeq++;
    _add(
      id,
      '${values['title'] ?? ''}',
      '${values['stage'] ?? ''}',
      by: by,
      holder: holder,
      completion: completion,
      tstruct: tstruct,
      ts: ts,
    );
    final r = _find(id);
    r['values'] = <String, dynamic>{...(r['values'] as Map), ...values};
    if (participants.isNotEmpty) {
      r['participants'] = {
        ...(r['participants'] as List),
        ...participants,
      }.toList();
    }
    return id;
  }

  /// The records of one structure as the server holds them (copies).
  static List<Map<String, dynamic>> recordsOf(String tstruct) => [
    for (final r in _records)
      if (r['tstruct'] == tstruct)
        {
          ...r,
          'values': {...(r['values'] as Map)},
        },
  ];

  /// Smart View's demo: record [id] moves to [status]; returns the changed
  /// record, or null when there is none.
  static Map<String, dynamic>? setDemoStatus(int id, String status) {
    final r = _records.where((x) => x['id'] == id).firstOrNull;
    if (r == null) return null;
    (r['values'] as Map)['stage'] = status;
    r['editedTs'] = _now;
    return {...r};
  }

  /// A record saved from the form screen in the demo: the form's automatic
  /// send puts it with a technician. Returns its id.
  static int addFromForm(String tstruct, Map<String, dynamic> values) {
    final id = _seq++;
    final first =
        (((_formOf(tstruct) as Map)['status'] as Map)['statuses'] as List)
            .first;
    _add(
      id,
      '${values['title'] ?? 'Untitled'}',
      '$first',
      by: me,
      holder: 'sam',
      assignor: me,
      tstruct: tstruct,
      ts: _now,
    );
    _log(id, 'created', by: me);
    return id;
  }

  /// A ticket is raised to me; returns its id.
  static int addAssignedToMe() {
    final id = _seq++;
    _add(id, 'Projector bulb out', 'Open', by: 'rhea', holder: me, ts: _now);
    _log(id, 'created', by: 'rhea');
    return id;
  }

  /// A ticket I raised that waits for approval; returns its id.
  static int addAwaitingApproval() {
    final id = _seq++;
    _add(
      id,
      'Parking pass',
      'Open',
      by: me,
      holder: me,
      pending: true,
      ts: _now,
    );
    _log(id, 'sent_for_approval', by: me);
    return id;
  }

  static void _log(
    int id,
    String op, {
    required String by,
    Map<String, dynamic> extra = const {},
  }) {
    final r = _find(id);
    (_events[id] ??= []).add({
      'id': _eventSeq++,
      'op': op,
      'by': by,
      'ts': _now,
      'record': id,
      'structure': r['tstruct'],
      'caption': (_formOf('${r['tstruct']}') as Map)['caption'],
      ...extra,
    });
  }

  static Map<String, dynamic> _find(int id) => _records.firstWhere(
    (r) => r['id'] == id,
    orElse: () => throw const SocketCallError('not_found', 'No such record.'),
  );

  static Map<String, dynamic> _spec(Map<String, dynamic> r) =>
      ((_formOf('${r['tstruct']}') as Map)['status'] as Map)
          .cast<String, dynamic>();

  static String _statusOf(Map<String, dynamic> r) =>
      '${(r['values'] as Map)['stage']}';

  static bool _isFinal(Map<String, dynamic> r) =>
      (_spec(r)['final'] as List).contains(_statusOf(r));

  static bool _isPending(Map<String, dynamic> r) => r['status'] == 'pending';

  /// The server in one function. Throws [SocketCallError] like a refused
  /// call; [isLosingNextAnswer] makes the call do its work and then time out.
  static Map<String, dynamic> answer(String cmd, Map<String, dynamic> args) {
    final isWrite = cmd == RecordCmd.status || cmd == RecordCmd.send;
    if (isWrite) {
      final error = nextError;
      if (error != null) {
        nextError = null;
        throw error;
      }
    }
    switch (cmd) {
      case RecordCmd.mine:
        return _mine(args);
      case RecordCmd.get:
        return {'submission': _view(_find(intOf(args['id'])))};
      case RecordCmd.actions:
        return _actions(_find(intOf(args['id'])));
      case RecordCmd.history:
        return _history(_find(intOf(args['id'])));
      case RecordCmd.targets:
        final r = _find(intOf(args['id']));
        return {
          'unrestricted': true,
          'designations': <String>[],
          'categories': <String>[],
          'initiator': r['by'],
          'assignor': r['assignor'] == '' ? null : r['assignor'],
          'blocked': false,
        };
      case RecordCmd.people:
        _find(intOf(args['id']));
        final q = '${args['q'] ?? ''}'.toLowerCase();
        final rows = [
          for (final e in people.entries)
            if (e.key != me &&
                (q.isEmpty || e.value.$1.toLowerCase().contains(q)))
              {
                'username': e.key,
                'name': e.value.$1,
                'designation': e.value.$2,
              },
        ];
        return {'people': rows, 'total': rows.length};
      case RecordCmd.thread:
        final r = _find(intOf(args['id']));
        if ((_formOf('${r['tstruct']}') as Map)['recordThread'] != true) {
          throw const SocketCallError('not_found', 'No such record.');
        }
        return {
          'conversation': 'group:rec-${r['tstruct']}-${r['id']}',
          'id': r['id'],
          'title': '${(r['values'] as Map)['title']}',
        };
      case RecordCmd.status:
      case RecordCmd.send:
        return _write(cmd, args);
    }
    throw SocketCallError('unknown_action', 'Unknown sd action: $cmd');
  }

  static Map<String, dynamic> _view(Map<String, dynamic> r) => {
    for (final e in r.entries)
      if (e.key != 'participants' && e.key != 'hours') e.key: e.value,
  };

  static Map<String, dynamic> _mine(Map<String, dynamic> args) {
    final as = '${args['as'] ?? 'with'}';
    final offset = intOf(args['offset']).clamp(0, 1 << 30);
    final isRaised = as == 'raised';
    final limit = intOf(args['limit'] ?? 100).clamp(1, 200);
    bool inList(Map<String, dynamic> r) => switch (as) {
      'raised' => r['by'] == me && r['holder'] != me || _isPending(r),
      'involved' =>
        r['by'] != me &&
            (r['participants'] as List).contains(me) &&
            r['holder'] != me,
      _ => r['holder'] == me && !_isPending(r) && !_isFinal(r),
    };
    final all = [
      for (final r in _records)
        if (inList(r)) r,
    ]..sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
    // `raised` copies the server's defect: it reads a chunk of 200 entries,
    // keeps at most `limit` records and moves past the whole chunk, so the
    // rest of the chunk is lost and the answer says there is no more.
    final chunkEnd = isRaised ? offset + raisedChunk : 0;
    final page = all
        .skip(offset)
        .take(isRaised ? limit : limit.clamp(1, pageCap))
        .toList();
    final forms = {
      for (final r in page) '${r['tstruct']}': _formOf('${r['tstruct']}'),
    };
    return {
      'submissions': [for (final r in page) _view(r)],
      'structures': forms,
      'total': isRaised ? page.length : all.length,
      'hasMore': isRaised
          ? chunkEnd < all.length
          : offset + page.length < all.length,
      'next': isRaised && chunkEnd < all.length ? chunkEnd : null,
    };
  }

  static Map<String, dynamic> _actions(Map<String, dynamic> r) {
    if (r['id'] == demoNotFound) {
      throw const SocketCallError('not_found', 'No such record.');
    }
    final out = _fullActions(r);
    final items = (out['items'] as List).cast<Map<String, dynamic>>();
    switch (r['id']) {
      case demoNoSend:
        items.removeWhere((i) => i['id'] == 'send');
      case demoNoStatus:
        items.removeWhere((i) => i['id'] == 'status');
      case demoSendOff:
        for (final i in items) {
          if (i['id'] == 'send') {
            i['enabled'] = false;
            i['why'] = 'Send is not allowed at this stage.';
          }
        }
    }
    return out;
  }

  static Map<String, dynamic> _fullActions(Map<String, dynamic> r) {
    final spec = _spec(r);
    final isHolder = r['holder'] == me;
    final waiting = _isPending(r);
    final isFinal = _isFinal(r);
    String? why;
    if (waiting) {
      why = 'This record is waiting for approval.';
    } else if (!isHolder) {
      why = 'Only the person it is with can do this.';
    }
    return {
      'items': [
        {'id': 'send', 'label': 'Send', 'enabled': why == null, 'why': ?why},
        {
          'id': 'status',
          'label': 'Update status',
          'enabled': why == null && !isFinal,
          'why':
              ?(why ??
              (isFinal
                  ? 'This record is ${_statusOf(r)}; only an administrator can change it.'
                  : null)),
        },
      ],
      'holder': r['holder'],
      'claimants': <String>[],
      'initiator': r['by'],
      'assignor': r['assignor'] == '' ? null : r['assignor'],
      'status': _statusOf(r),
      'statuses': spec['statuses'],
      'final': spec['final'],
      'completion': r['completion'],
      'hours': r['hours'],
      'commentsRequired': r['tstruct'] == 'help_task',
      'completionRequired': r['tstruct'] == 'help_task',
      'hoursRequired': r['tstruct'] == 'help_task',
      'filesRequired': r['tstruct'] == 'help_task',
      'isAdmin': _adminIds.contains(r['id']),
      'hasRules': false,
      'lastUpdate': null,
      'files': <String>[],
    };
  }

  static Map<String, dynamic> _history(Map<String, dynamic> r) => {
    'caption': (_formOf('${r['tstruct']}') as Map)['caption'],
    'events': _events[r['id']] ?? <Map<String, dynamic>>[],
    'fields': (_formOf('${r['tstruct']}') as Map)['fields'],
    'names': {for (final e in people.entries) e.key: e.value.$1},
    'files': <String, dynamic>{},
    'sections': <String, dynamic>{},
    'status': 'record',
  };

  static Map<String, dynamic> _write(String cmd, Map<String, dynamic> args) {
    final id = intOf(args['id']);
    final r = _find(id);
    final requestId = '${args['requestId'] ?? ''}';
    if (requestId.isNotEmpty) {
      requestIds.add(requestId);
      final first = _answers['$id/$requestId'];
      if (first != null) return {...first, 'repeated': true};
    }
    final expected = args['expected'];
    if (expected is Map) {
      final s = expected['status'];
      final h = expected['holder'];
      if ((s != null && s != _statusOf(r)) || (h != null && h != r['holder'])) {
        throw const SocketCallError(
          'stale',
          'This record was updated by someone else. Reload to see the latest.',
        );
      }
    }
    if (_isPending(r)) {
      throw const SocketCallError(
        'invalid',
        'This record is waiting for approval; nobody can act on it yet.',
      );
    }
    if (r['holder'] != me) {
      throw const SocketCallError(
        'forbidden',
        'Only the person it is with can do this.',
      );
    }
    final out = cmd == RecordCmd.status
        ? _setStatus(r, args)
        : _doSend(r, args);
    if (requestId.isNotEmpty) _answers['$id/$requestId'] = out;
    // The server tells the actor too (submissions_changed); the new holder
    // of a Send is another person's device, nothing for this phone.
    _emit('submissions_changed', {
      'id': id,
      'tstruct': r['tstruct'],
      'action': cmd == RecordCmd.status ? 'Status update' : 'Send',
    });
    if (isLosingNextAnswer) {
      isLosingNextAnswer = false;
      throw const SocketCallError('timeout');
    }
    return out;
  }

  static Map<String, dynamic> _setStatus(
    Map<String, dynamic> r,
    Map<String, dynamic> args,
  ) {
    if (_isFinal(r)) {
      throw SocketCallError(
        'invalid',
        'This record is ${_statusOf(r)}; only an administrator can change it.',
      );
    }
    final spec = _spec(r);
    final next = '${args['status'] ?? ''}';
    if (!(spec['statuses'] as List).contains(next)) {
      throw const SocketCallError(
        'invalid',
        'Choose one of the statuses of this record.',
      );
    }
    final comments = '${args['comments'] ?? ''}'.trim();
    if (r['tstruct'] == 'help_task' && comments.isEmpty) {
      throw const SocketCallError('invalid', 'Add your comments.');
    }
    final percent = args['percent'];
    if (percent != null && intOf(percent) < intOf(r['completion'])) {
      throw const SocketCallError('invalid', 'Completion cannot go down.');
    }
    final hours = args['hours'];
    final h = hours == null ? null : double.tryParse('$hours');
    if (hours != null &&
        (h == null ||
            h < 0 ||
            h > 24 ||
            !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch('$hours'))) {
      throw const SocketCallError(
        'invalid',
        'Hours worked must be a number from 0 to 24, with at most two decimals.',
      );
    }
    final from = _statusOf(r);
    if (next == from && percent == null && hours == null) {
      throw SocketCallError('invalid', 'It is already $from.');
    }
    (r['values'] as Map)['stage'] = next;
    if (percent != null) r['completion'] = intOf(percent);
    if (hours != null) r['hours'] = '$hours';
    r['editedTs'] = _now;
    final isFinal = (spec['final'] as List).contains(next);
    _log(
      r['id'] as int,
      'status',
      by: me,
      extra: {
        'fromStatus': from,
        'toStatus': next,
        'completion': '${r['completion']}',
        if (hours != null) 'hours': '$hours',
        if (comments.isNotEmpty) 'remarks': comments,
        'final': isFinal,
        'files': (args['files'] as List?) ?? <String>[],
        'asAdmin': false,
      },
    );
    return {
      'id': r['id'],
      'holder': r['holder'],
      'status': next,
      'completion': r['completion'],
      'hours': r['hours'],
      'final': isFinal,
      'files': (args['files'] as List?) ?? <String>[],
    };
  }

  static Map<String, dynamic> _doSend(
    Map<String, dynamic> r,
    Map<String, dynamic> args,
  ) {
    final via = '${args['via'] ?? ''}';
    final String to;
    switch (via) {
      case 'user':
        to = '${args['person'] ?? ''}';
      case 'designation':
        final value = '${args['value'] ?? ''}'.toLowerCase();
        to = people.entries
            .firstWhere(
              (e) => e.value.$2.toLowerCase() == value && e.key != me,
              orElse: () => throw const SocketCallError(
                'invalid',
                'Nobody with that designation can take it.',
              ),
            )
            .key;
      case 'category':
        to = 'sam';
      case 'initiator':
        to = '${r['by']}';
      case 'assignor':
        to = '${r['assignor']}';
      default:
        throw const SocketCallError('bad_request', 'Choose who to send it to.');
    }
    if (!people.containsKey(to) || to.isEmpty) {
      throw const SocketCallError('invalid', 'Choose someone to send it to.');
    }
    if (to == me) {
      throw const SocketCallError('invalid', 'You cannot send it to yourself.');
    }
    if (to == r['holder']) {
      throw const SocketCallError('invalid', 'It is already with them.');
    }
    final from = '${r['holder']}';
    r['assignor'] = from;
    r['holder'] = to;
    r['editedTs'] = _now;
    (r['participants'] as List).add(to);
    _log(
      r['id'] as int,
      'sent',
      by: me,
      extra: {
        'to': [to],
        'via': via,
        'value': '${args['value'] ?? ''}',
        'fromHolder': from,
        if ('${args['reason'] ?? ''}'.isNotEmpty) 'reason': '${args['reason']}',
        if ('${args['remarks'] ?? ''}'.isNotEmpty)
          'remarks': '${args['remarks']}',
        'status': _statusOf(r),
        'files': (args['files'] as List?) ?? <String>[],
        'asAdmin': false,
      },
    );
    return {
      'id': r['id'],
      'holder': to,
      'assignor': from,
      'status': _statusOf(r),
      'completion': r['completion'],
      'files': (args['files'] as List?) ?? <String>[],
    };
  }
}
