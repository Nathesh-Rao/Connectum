import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/records_log.dart';
import '../../core/debug/seed_tickets.dart';
import '../models/ids.dart';
import '../models/record_live.dart';
import '../models/record_state.dart';
import '../models/ticket.dart';
import '../records/record_actions_queue.dart';
import '../records/record_commands.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'conversation_repository.dart';
import '../../core/log/safe.dart';

typedef _Read = ({Map<String, dynamic>? data, SocketCallError? error});

/// A record read in full: the submission and what `record.actions` says.
///
/// Two known BE gaps are told here, not thrown (`MOBILE_RECORDS_FULL.md`,
/// Findings 1 and 2): [isReadOnly] is a record that opens but whose
/// `record.actions` answers `not_found` (an approver of an open stage, a
/// notified person), [isUnopenable] a record the list showed but
/// `submission.get` refuses (a person who sees every record of the form).
class TicketDetail {
  const TicketDetail({
    required this.ticket,
    required this.state,
    this.isReadOnly = false,
    this.isUnopenable = false,
  });

  final Ticket ticket;
  final RecordState state;
  final bool isReadOnly;
  final bool isUnopenable;
}

/// The record flow: `records.mine`, `submission.get`, `record.actions`,
/// `submission.history`, `record.status`, `record.send` and the helpers, plus
/// the events that say something changed. Nothing is kept but the badge number
/// and the last records read (so a detail opens at once); the screens own
/// their lists and read again when [refreshes] fires (reconnect, resume, any
/// record event, debounced), because the server has no "changed since" read
/// and events sent while offline are lost.
class TicketRepository extends GetxService with WidgetsBindingObserver {
  TicketRepository(
    this._socket,
    this._store,
    this._conversations, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _queue = RecordActionsQueue(
      now: _now,
      fetch: _fetchForCard,
      isFresh: _isMenuFresh,
      canRun: () => SeedTickets.isActive || _socket.isOnline,
    );
  }

  final SocketService _socket;
  final SessionStore _store;
  final ConversationRepository _conversations;

  /// The clock; tests give a fake one.
  final DateTime Function() _now;

  static const pageSize = 100;
  static const burst = Duration(milliseconds: 300);

  /// How many records are with this person now (the badge).
  final withTotal = 0.obs;

  late final RecordActionsQueue _queue;

  /// The queue that reads `record.actions` for cards on screen.
  RecordActionsQueue get actionsQueue => _queue;

  final _refreshes = StreamController<void>.broadcast();
  final _assigned = StreamController<TicketAssigned>.broadcast();
  final _known = <int, Ticket>{};
  final _forms = <String, TicketForm>{};
  final _states = <int, RecordState>{};
  final _names = <String, String>{};
  Timer? _burst;
  StreamSubscription<Map<String, dynamic>>? _events;
  StreamSubscription<void>? _online;

  /// Read the lists and the open record again.
  Stream<void> get refreshes => _refreshes.stream;

  /// A record is now with this person (only the new holder gets it).
  Stream<TicketAssigned> get assigned => _assigned.stream;

  String get me => (SeedTickets.isActive ? SeedTickets.me : _store.userId ?? '')
      .toLowerCase();

  bool isMe(String user) => user.isNotEmpty && user.toLowerCase() == me;

  /// The last read of record [id], if any.
  Ticket? known(int id) => _known[id];

  /// Changes whenever a known record changes, so a card reading it rebuilds.
  final cardRevision = 0.obs;
  static const cardTtl = Duration(seconds: 60);
  final _readAt = <int, DateTime>{};
  final _reading = <int, Future<void>>{};
  final _menuAt = <int, DateTime>{};
  final _menuReading = <int, Future<void>>{};
  final _listed = <int>{};
  final _live = <int, Rx<RecordLive>>{};
  bool _isAllStale = false;
  final _unopenableAt = <int, DateTime>{};
  int cardReads = 0;

  /// What a chat card needs to draw its actions, from the last read. Reading
  /// [cardRevision] first makes an `Obx` follow it.
  RecordState? stateOf(int id) {
    cardRevision.value;
    return _states[id];
  }

  /// What the card of record [id] shows. One observable per record, so a
  /// change rebuilds that card only. Nothing is read for it: it follows the
  /// reads, the answers of my own actions and the events.
  Rx<RecordLive> liveOf(int id) =>
      _live.putIfAbsent(id, () => Rx<RecordLive>(const RecordLive()));

  /// The enabled actions of record [id] from its last read, for a card's bar.
  /// Follows [liveOf] (not [cardRevision]), so only that card rebuilds.
  List<RecordActionItem> itemsOf(int id) {
    final live = liveOf(id).value;
    if (live.isStale) return const [];
    return _states[id]?.offered ?? const [];
  }

  void _setLive(int id, RecordLive next, {bool isForced = false}) {
    final rx = liveOf(id);
    // A read does not say when the record last changed: what the last summary
    // said about that is kept, so a late older summary cannot undo the read.
    if (next.summaryTs == 0 && rx.value.summaryTs > 0) {
      next = next.copyWith(summaryTs: rx.value.summaryTs);
    }
    if (!isForced && rx.value.sameAs(next)) return;
    rx.value = next;
  }

  /// Applies a `record` summary (an event, a card, `records.summary`) to the
  /// card of record [id] at once, with no command. One older than or equal to
  /// the last applied is ignored. When the record's status, holder or closing
  /// changed, the cached actions are dropped (the bar hides now) and read
  /// again if the card is on screen, or the next time the menu opens.
  /// Returns whether it was applied.
  bool applySummary(int id, RecordSummary summary, {String initiator = ''}) {
    final cur = liveOf(id).value;
    if (cur.summaryTs > 0 && summary.ts <= cur.summaryTs) return false;
    final next = cur.withSummary(
      summary,
      initiator: initiator.isNotEmpty ? initiator : _known[id]?.by ?? '',
    );
    final isChanged =
        cur.isKnown &&
        (cur.status != next.status ||
            cur.holder != next.holder ||
            cur.isFinal != next.isFinal ||
            cur.claimants.join(',') != next.claimants.join(','));
    _setLive(id, next);
    if (isChanged) {
      _readAt.remove(id);
      _menuAt.remove(id);
      _states.remove(id);
      _queue.markStale(id);
    }
    cardRevision.value++;
    return true;
  }

  // ---- records.summary ----------------------------------------------------------

  /// One `records.summary` takes at most this many ids.
  static const summaryChunk = 50;

  /// Gap between two summary calls: 30 commands per 10 s is the limit and the
  /// actions queue and chat traffic share it.
  static const summarySpacing = Duration(milliseconds: 500);
  static const _summaryDebounce = Duration(milliseconds: 150);

  final _summaryWanted = <int>{};
  final _summaryInFlight = <int>{};
  Timer? _summaryTimer;
  bool _isSummaryRunning = false;

  /// Commands `records.summary` sent so far (tests).
  int summaryCalls = 0;

  /// A card of record [id] came on screen with the `record` object it was
  /// delivered with (applied now) or without one (the record is unknown: it is
  /// asked for in a batch).
  void showSummary(int id, RecordSummary? summary) {
    if (summary != null) {
      applySummary(id, summary);
      return;
    }
    if (!liveOf(id).value.isKnown) requestSummaries([id]);
  }

  /// Ids whose summary is missing or old (no `record` came, a reconnect, a
  /// thread opened): asked for in chunks of [summaryChunk], one call at a
  /// time, [summarySpacing] apart; an id already asked for is not asked again.
  void requestSummaries(Iterable<int> ids) {
    for (final id in ids) {
      if (id > 0 && !_summaryInFlight.contains(id)) _summaryWanted.add(id);
    }
    if (_summaryWanted.isEmpty) return;
    _summaryTimer ??= Timer(_summaryDebounce, () {
      _summaryTimer = null;
      _pumpSummaries();
    });
  }

  Future<void> _pumpSummaries() async {
    if (_isSummaryRunning) return;
    _isSummaryRunning = true;
    try {
      while (_summaryWanted.isNotEmpty) {
        if (!(SeedTickets.isActive || _socket.isOnline)) return;
        final chunk = _summaryWanted.take(summaryChunk).toList();
        _summaryWanted.removeAll(chunk);
        _summaryInFlight.addAll(chunk);
        summaryCalls++;
        try {
          final data = await _call(RecordCmd.summary, {'ids': chunk});
          final rows = data['summaries'];
          if (rows is List) {
            for (final row in rows) {
              if (row is! Map) continue;
              final id = idNumber(row['id']);
              final summary = RecordSummary.tryParse(row['record']);
              if (id != null && summary != null) applySummary(id, summary);
            }
          }
        } on SocketCallError catch (e) {
          if (e.code == 'rate_limited' || e.code == 'busy') {
            _summaryWanted.addAll(chunk);
            await Future<void>.delayed(summarySpacing * 4);
          }
        } finally {
          _summaryInFlight.removeAll(chunk);
        }
        if (_summaryWanted.isNotEmpty) {
          await Future<void>.delayed(summarySpacing);
        }
      }
    } finally {
      _isSummaryRunning = false;
    }
  }

  /// Reads record [id] in full (`submission.get` + `record.actions`) when the
  /// last read is older than [cardTtl] or an event made it stale. For the
  /// record screens that need the values; cards use [ensureMenu].
  Future<void> ensure(int id) {
    final at = _readAt[id];
    if (at != null && _now().difference(at) < cardTtl) {
      return Future.value();
    }
    return _reading[id] ??= _readFull(id).whenComplete(() {
      _reading.remove(id);
    });
  }

  Future<void> _readFull(int id) async {
    try {
      await get(id);
    } on SocketCallError {
      // The caller keeps what it has.
    }
    _readAt[id] = _now();
  }

  /// Reads `record.actions` of record [id] for a card's menu when the last
  /// read is older than [cardTtl] or an event made it stale. Called only when
  /// the person opens the menu, never from a card being drawn. One read per
  /// record at a time; a refused or failed read is kept for the same
  /// [cardTtl], so it is not repeated.
  Future<void> ensureMenu(int id) {
    final at = _menuAt[id];
    if (at != null && _now().difference(at) < cardTtl) {
      return Future.value();
    }
    return _menuReading[id] ??= _readMenu(id).whenComplete(() {
      _menuReading.remove(id);
    });
  }

  /// Cards on screen ask for their actions here, never anywhere else. The
  /// queue sends them one at a time inside its budget; a record with a fresh
  /// read costs nothing.
  void loadActions(Iterable<int> ids) => ids.forEach(_queue.show);

  /// Those cards left the screen (or their screen was covered).
  void releaseActions(Iterable<int> ids) => ids.forEach(_queue.hide);

  bool _isMenuFresh(int id) {
    final at = _menuAt[id];
    return at != null && _now().difference(at) < cardTtl;
  }

  /// One queued read. A retryable refusal is thrown to the queue; any other
  /// outcome (no such record, a reply that cannot be read) is kept for
  /// [cardTtl] with no actions, and logged.
  Future<void> _fetchForCard(int id) {
    final running = _menuReading[id];
    if (running != null) return running;
    return _menuReading[id] = _readQueued(id).whenComplete(() {
      _menuReading.remove(id);
      cardRevision.value++;
    });
  }

  Future<void> _readQueued(int id) async {
    cardReads++;
    cardRevision.value++;
    try {
      await actions(id);
    } on SocketCallError catch (e) {
      if (RecordActionsQueue.retryable.contains(e.code) || e.isConnectionGap) {
        RecordsLog.line('card id=$id record.actions -> ${e.code}, will retry');
        rethrow;
      }
      RecordsLog.line('card id=$id record.actions -> ${e.code}, no actions');
      _states.remove(id);
    } catch (e) {
      RecordsLog.line('card id=$id record.actions unreadable ($e), no actions');
      _states.remove(id);
    }
    _menuAt[id] = _now();
  }

  /// A menu read of [id] is running (reads [cardRevision] first).
  bool isCardReading(int id) {
    cardRevision.value;
    return _menuReading.containsKey(id);
  }

  Future<void> _readMenu(int id) async {
    cardReads++;
    try {
      await actions(id);
    } on SocketCallError catch (e) {
      RecordsLog.line('card menu id=$id record.actions -> ${e.code}');
    }
    _menuAt[id] = _now();
    cardRevision.value++;
  }

  /// A person's display name when it is known, else the username.
  String nameOf(String user) {
    if (user.isEmpty) return user;
    final saved = _names[user.toLowerCase()];
    if (saved != null) return saved;
    final dm = 'dm:${user.toLowerCase()}';
    for (final c in _conversations.conversations) {
      if (c.convId.toLowerCase() == dm && c.title.trim().isNotEmpty) {
        return c.title;
      }
    }
    return user;
  }

  /// Remembers a name seen in a picker or a history.
  void rememberName(String user, String name) {
    if (user.isNotEmpty && name.trim().isNotEmpty) {
      _names[user.toLowerCase()] = name;
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _events = _socket.events.listen(onEvent, onError: streamOnError('ticket_repository'));
    SeedTickets.emit = onEvent;
    _online = _socket.onOnline.listen((_) {
      _queue.resume();
      _logSession();
      scheduleRefresh();
    }, onError: streamOnError('ticket_repository'));
    ever(_store.current, (_) => _reset());
  }

  String? _loggedSession;

  /// Once per signed-in person and organisation: where this phone is
  /// connected and which workspaces the person has (debug builds only).
  void _logSession() {
    if (!kDebugMode) return;
    final key = '${_store.orgId}/${_store.userId}';
    if (_loggedSession == key) return;
    _loggedSession = key;
    final memberships = _store.identity.value?.enterprises ?? const [];
    RecordsLog.line(
      'session org=${_store.orgId} user=${_store.userId} '
      'connection=${_socket.connection.value.name} '
      'hasToken=${_store.hasSession} '
      'workspaces=${memberships.length} '
      '[${memberships.map((m) => '${m.enterprise}(${m.name}) as ${m.username} ${m.status}').join('; ')}]',
    );
  }

  /// Another person or organisation: nothing of the last one stays (record
  /// ids are per organisation, the same number is another record there).
  void _reset() {
    _burst?.cancel();
    _queue.clear();
    _known.clear();
    _forms.clear();
    _states.clear();
    _readAt.clear();
    _menuAt.clear();
    _reading.clear();
    _menuReading.clear();
    _listed.clear();
    _live.clear();
    _summaryWanted.clear();
    _summaryInFlight.clear();
    _unopenableAt.clear();
    _names.clear();
    withTotal.value = 0;
    cardRevision.value++;
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _burst?.cancel();
    _summaryTimer?.cancel();
    _queue.dispose();
    _events?.cancel();
    _online?.cancel();
    _refreshes.close();
    _assigned.close();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queue.resume();
      scheduleRefresh();
    } else {
      _queue.pause();
    }
  }

  /// Bursts of events become one read (300 ms). [isAll]: no record is named
  /// (a reconnect, the app resumed): every cached menu is old.
  void scheduleRefresh({bool isAll = true}) {
    if (isAll) _isAllStale = true;
    _burst?.cancel();
    _burst = Timer(burst, () {
      if (_isAllStale) invalidate();
      _isAllStale = false;
      cardRevision.value++;
      if (!_refreshes.isClosed) _refreshes.add(null);
    });
  }

  /// A reconnect or a resume: every cached menu is old and every card marked
  /// so. Cards show no action bar until the person opens the menu again; what
  /// they show of the record stays.
  void invalidate() {
    _readAt.clear();
    _menuAt.clear();
    _states.clear();
    _unopenableAt.clear();
    for (final id in _live.keys.toList()) {
      final live = _live[id]!.value;
      if (live.isKnown) _setLive(id, live.copyWith(isStale: true));
    }
    _queue.markAllStale();
    requestSummaries([
      for (final id in _live.keys)
        if (_queue.isVisible(id)) id,
    ]);
  }

  /// An event named record [id]: only that record's cached reads are old and
  /// only its card changes. No command is sent.
  void _touch(int id, {String action = '', String? holder}) {
    _readAt.remove(id);
    _menuAt.remove(id);
    _states.remove(id);
    final live = liveOf(id).value;
    _setLive(
      id,
      live.copyWith(
        isStale: true,
        lastAction: action.isEmpty ? live.lastAction : action,
        holder: holder,
      ),
    );
    _queue.markStale(id);
  }

  /// The event's `record` object, applied to the card at once. False when it
  /// had none (or an old one): the caller marks the record stale instead.
  bool _applyEventSummary(
    int id,
    Map<dynamic, dynamic> data, {
    String action = '',
  }) {
    final summary = RecordSummary.tryParse(data['record']);
    if (summary == null) return false;
    final applied = applySummary(id, summary);
    if (applied && action.isNotEmpty) {
      final live = liveOf(id).value;
      _setLive(id, live.copyWith(lastAction: action));
    }
    return true;
  }

  static const _watched = {
    RecordEvents.changed,
    RecordEvents.assigned,
    RecordEvents.formMessage,
    RecordEvents.formMessageUpdated,
  };

  /// Public so the debug page and tests can feed it events.
  void onEvent(Map<String, dynamic> e) {
    final name = e['type'] == 'sd_event' ? e['event'] : e['type'];
    if (!_watched.contains(name)) return;
    final raw = e['data'];
    final data = raw is Map ? raw : e;
    if (name == RecordEvents.assigned) {
      final assigned = TicketAssigned.tryParse(data);
      if (assigned != null && !_assigned.isClosed) _assigned.add(assigned);
      // Only the new holder gets it: the record is with me now.
      if (assigned != null) {
        if (!_applyEventSummary(assigned.id, data, action: assigned.action)) {
          _touch(assigned.id, action: assigned.action, holder: me);
          requestSummaries([assigned.id]);
        }
      }
      scheduleRefresh(isAll: assigned == null);
      return;
    }
    if (name == RecordEvents.changed) {
      final id = idNumber(data['id']);
      if (id != null) {
        final action = idText(data['action']);
        if (action.toLowerCase() == 'deleted') {
          _touch(id, action: action);
        } else if (!_applyEventSummary(id, data, action: action)) {
          _touch(id, action: action);
          if (liveOf(id).value.isKnown || _queue.isVisible(id)) {
            requestSummaries([id]);
          }
        }
      }
      scheduleRefresh(isAll: id == null);
      return;
    }
    // A card was posted or rewritten: it carries the record's state for a
    // person who may read it; without one the record is unknown.
    final form = data['form'];
    if (form is Map) {
      final id = idNumber(form['submissionId']);
      final summary = RecordSummary.tryParse(form['record']);
      if (id != null && summary != null) applySummary(id, summary);
    }
    scheduleRefresh(isAll: false);
  }

  // ---- calls -----------------------------------------------------------------

  Future<Map<String, dynamic>> _call(String cmd, Map<String, dynamic> args) {
    if (SeedTickets.isActive) {
      try {
        return Future.value(SeedTickets.answer(cmd, args));
      } on SocketCallError catch (e) {
        return Future.error(e);
      }
    }
    return _logged(cmd, args);
  }

  static const _logCmds = {RecordCmd.mine, RecordCmd.get, RecordCmd.actions};

  Future<Map<String, dynamic>> _logged(
    String cmd,
    Map<String, dynamic> args,
  ) async {
    if (!kDebugMode || !_logCmds.contains(cmd)) {
      return _socket.sdCall(cmd, args);
    }
    final org = _store.orgId ?? '-';
    final user = _store.userId ?? '-';
    try {
      final reply = await _socket.sdCall(cmd, args);
      RecordsLog.call(cmd, args, org: org, user: user, reply: reply);
      return reply;
    } on SocketCallError catch (e) {
      RecordsLog.call(cmd, args, org: org, user: user, error: e.code);
      rethrow;
    }
  }

  /// One page of `records.mine`. [as]: with | raised | involved (`all` is for
  /// administrators and is never asked for here). [offset]: how many rows the
  /// screen already holds. A page can hold fewer rows than [limit] while
  /// `hasMore` is true. `raised` always asks for 200 ([RecordLimits.mineLimit]);
  /// `with` and `involved` continue at offset + rows received, `raised` at the
  /// server's `next`.
  Future<TicketPage> mine({
    required String as,
    int offset = 0,
    int limit = pageSize,
  }) async {
    final data = await _call(RecordCmd.mine, {
      'as': as,
      'limit': RecordLimits.mineLimit(as, limit),
      if (offset > 0) 'offset': offset,
    });
    final page = TicketPage.parse(data);
    _remember(page);
    if (as == 'with') withTotal.value = page.total;
    return page;
  }

  void _remember(TicketPage page) {
    _forms.addAll(page.forms);
    for (final t in page.tickets) {
      _known[t.id] = t;
      _listed.add(t.id);
      _setLive(t.id, liveOf(t.id).value.withTicket(t));
    }
    if (page.tickets.isNotEmpty) cardRevision.value++;
  }

  Future<_Read> _read(String cmd, int id) async {
    try {
      return (data: await _call(cmd, {'id': id}), error: null);
    } on SocketCallError catch (e) {
      return (data: null, error: e);
    }
  }

  /// One record with its actions. Throws [SocketCallError] when the server
  /// refuses (`not_found` also covers a record this person may not see),
  /// except the two known BE gaps (see [TicketDetail]).
  Future<TicketDetail> get(int id) async {
    final skipGet = _isUnopenable(id);
    final results = await Future.wait([
      skipGet
          ? Future<_Read>.value((data: null, error: null))
          : _read(RecordCmd.get, id),
      _read(RecordCmd.actions, id),
    ]);
    final sub = results[0];
    final act = results[1];
    var isReadOnly = false;
    var isUnopenable = false;
    Ticket? ticket;
    if (sub.data != null) {
      ticket = Ticket.tryParse(sub.data!['submission'], _forms);
      if (ticket == null) {
        throw const SocketCallError('error', 'The server sent no record.');
      }
    } else if (skipGet || sub.error?.code == 'not_found') {
      final listed = _listed.contains(id) ? _known[id] : null;
      if (listed == null) throw sub.error ?? const SocketCallError('not_found');
      ticket = listed;
      isUnopenable = true;
      _unopenableAt[id] = _now();
      RecordsLog.line(
        'id=$id listed but submission.get not_found: BE gap, '
        'showing the list row',
      );
    } else {
      throw sub.error!;
    }
    var state = const RecordState(items: []);
    if (act.data != null) {
      state = RecordState.parse(act.data!);
    } else if (act.error?.code == 'not_found') {
      isReadOnly = !isUnopenable;
      if (isReadOnly) {
        RecordsLog.line(
          'id=$id submission.get ok but record.actions not_found: BE gap, '
          'opened read-only',
        );
      }
    } else if (!isUnopenable) {
      throw act.error!;
    }
    ticket = ticket.copyWith(
      holder: state.holder.isEmpty ? ticket.holder : state.holder,
      assignor: state.assignor.isEmpty ? ticket.assignor : state.assignor,
      completion: state.completion ?? ticket.completion,
    );
    _known[id] = ticket;
    _states[id] = state;
    if (act.data != null) {
      _setLive(id, RecordLive.fromState(state), isForced: true);
    }
    cardRevision.value++;
    return TicketDetail(
      ticket: ticket,
      state: state,
      isReadOnly: isReadOnly,
      isUnopenable: isUnopenable,
    );
  }

  bool _isUnopenable(int id) {
    final at = _unopenableAt[id];
    return at != null && _now().difference(at) < cardTtl;
  }

  /// Rows another list read (Smart View): their cards follow them like a
  /// `records.mine` row, with one rebuild for the lot.
  void rememberRows(Iterable<Ticket> rows) {
    for (final t in rows) {
      _known[t.id] = t;
      _listed.add(t.id);
      _setLive(t.id, liveOf(t.id).value.withTicket(t));
    }
    cardRevision.value++;
  }

  /// A record event that carried the record's state (`data.record`): the card
  /// shows it at once, no command.
  void setLiveFromEvent(int id, RecordLive next) => _setLive(id, next);

  /// A record a list row showed: opening it may be refused by the server
  /// (BE gap) and the row is then what the screen has.
  void listed(Ticket t) {
    _known[t.id] = t;
    _listed.add(t.id);
    cardRevision.value++;
  }

  /// `record.actions`: the menu and the state, read again after every action.
  Future<RecordState> actions(int id) async {
    final state = RecordState.parse(await _call(RecordCmd.actions, {'id': id}));
    _states[id] = state;
    _menuAt[id] = _now();
    _setLive(id, RecordLive.fromState(state), isForced: true);
    final t = _known[id];
    if (t != null) {
      _known[id] = t.copyWith(
        holder: state.holder,
        assignor: state.assignor,
        completion: state.completion ?? t.completion,
      );
    }
    cardRevision.value++;
    return state;
  }

  /// Oldest first.
  Future<RecordHistory> history(int id) async {
    final history = RecordHistory.parse(
      await _call(RecordCmd.history, {'id': id}),
    );
    history.names.forEach(rememberName);
    final t = _known[id];
    if (t != null && t.form == null && history.fields.isNotEmpty) {
      _known[id] = t.copyWith(
        form: TicketForm(
          key: t.tstruct,
          caption: history.caption.isEmpty ? t.tstruct : history.caption,
          fields: history.fields,
        ),
      );
    }
    return history;
  }

  /// One status update. [payload] is built by `RecordPayload.status`. Sent
  /// once; a retry of a lost answer carries the same `requestId`.
  Future<RecordPatch> setStatus(Map<String, dynamic> payload) async =>
      RecordPatch.parse(await _call(RecordCmd.status, payload));

  /// One manual send. [payload] is built by `RecordPayload.send`.
  Future<RecordPatch> send(Map<String, dynamic> payload) async =>
      RecordPatch.parse(await _call(RecordCmd.send, payload));

  Future<RecordTargets> targets(int id) async =>
      RecordTargets.parse(await _call(RecordCmd.targets, {'id': id}));

  Future<List<RecordPerson>> people(
    int id, {
    String q = '',
    String designation = '',
    String category = '',
  }) async => RecordPerson.parseAll(
    await _call(RecordCmd.people, {
      'id': id,
      if (q.trim().isNotEmpty) 'q': q.trim(),
      if (designation.isNotEmpty) 'designation': designation,
      if (category.isNotEmpty) 'category': category,
    }),
  );

  /// The record's conversation; throws `not_found` when it has none.
  Future<RecordThread?> thread(int id) async =>
      RecordThread.tryParse(await _call(RecordCmd.thread, {'id': id}));

  /// The patch of an action I made, applied to what is known.
  Ticket? applied(int id, RecordPatch patch) {
    final t = _known[id];
    if (t == null) return null;
    final next = t.applying(patch);
    _known[id] = next;
    _setLive(
      id,
      liveOf(
        id,
      ).value.withPatch(patch, me: me, ts: _now().millisecondsSinceEpoch),
    );
    cardRevision.value++;
    return next;
  }

  /// A record this person just saved: its id, read for the first holder.
  Future<RecordState?> afterSave(int id) async {
    try {
      return await actions(id);
    } on SocketCallError {
      return null;
    }
  }
}
