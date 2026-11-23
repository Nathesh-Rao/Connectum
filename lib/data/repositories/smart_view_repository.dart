import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/records_log.dart';
import '../../core/debug/seed_smart_view.dart';
import '../commands/command_reply.dart';
import '../models/ids.dart';
import '../records/record_commands.dart';
import '../session_store.dart';
import '../smart_view/models/sv_row.dart';
import '../smart_view/overview/sv_overview.dart';
import '../smart_view/models/sv_source.dart';
import '../smart_view/smart_view_commands.dart';
import '../socket/socket_service.dart';
import 'ticket_repository.dart';
import '../../core/log/safe.dart';

enum SvPhase { loading, ready, empty, error, offline, noAccess }

/// The rows of one open structure, in memory only. The screen reads it; the
/// repository fills it. Hidden fields are cut out of every row when it is
/// read, so their values are never held.
class SvTable {
  SvTable(this.source);

  final SvSource source;
  final rows = <SvRow>[].obs;
  final phase = SvPhase.loading.obs;

  /// More pages are being read; the rows so far are shown.
  final isPaging = false.obs;

  /// A page failed after some rows were read; Retry reads again.
  final hasPartialError = false.obs;

  /// `total` of `submissions.list`, for the "first N of M" line.
  final total = 0.obs;
  final isCapped = false.obs;
  final errorMessage = ''.obs;

  /// Ids a live event changed, and how often: a card fades in when its
  /// version changes. Empty for a plain load.
  final versions = <int, int>{}.obs;

  int loadId = 0;
  bool isLoading = false;

  SvRow? rowOf(int id) {
    for (final r in rows) {
      if (r.id == id) return r;
    }
    return null;
  }
}

/// Smart View's reads (phase 1: no client engine). Everything runs through
/// one gate: one command at a time, at least [SvLimits.gap] apart, at most
/// [SvLimits.budget] in any [SvLimits.window]; `rate_limited` and `busy` wait
/// 1, 2, 3, 4 s and retry. Rows are never written to SQLite or a log.
class SmartViewRepository extends GetxService with WidgetsBindingObserver {
  SmartViewRepository(
    this._socket,
    this._store,
    this._tickets, {
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    Duration gap = SvLimits.gap,
    Duration debounce = SvLimits.eventDebounce,
  }) : _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       _gap = gap,
       _debounce = debounce;

  final SocketService _socket;
  final SessionStore _store;
  final TicketRepository _tickets;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final Duration _gap;
  final Duration _debounce;

  List<SvSource>? _sources;
  Future<List<SvSource>>? _sourcesLoading;

  /// How often the source list was read since the last organisation switch.
  int sourceReads = 0;

  /// Commands sent so far (tests).
  int sent = 0;
  final _starts = <DateTime>[];
  DateTime? _lastStart;
  Future<void> _tail = Future.value();
  int _epoch = 0;

  final _tables = <SvTable>[];
  StreamSubscription<Map<String, dynamic>>? _events;
  StreamSubscription<void>? _online;

  /// `record` when events carry `data.record`, `refetch` when they do not;
  /// null until the first event.
  String? liveMode;

  final _dirtyIds = <SvTable, Set<int>>{};
  final _removed = <SvTable, Set<int>>{};
  final _needsNewest = <SvTable>{};
  final _needsFull = <SvTable>{};
  final _flushing = <SvTable>{};
  int _debounceGen = 0;

  String get me =>
      (SeedSmartView.isActive ? SeedSmartView.me : _store.userId ?? '')
          .toLowerCase();

  bool get isOnline => SeedSmartView.isActive || _socket.isOnline;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _events = _socket.events.listen(
      (event) => fireAndLog('smart_view_repository', () async => onEvent(event)),
      onError: streamOnError('smart_view_repository'),
    );
    SeedSmartView.emit = onEvent;
    _online = _socket.onOnline.listen((_) => _reconnected(), onError: streamOnError('smart_view_repository'));
    ever(_store.current, (_) => _reset());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    _online?.cancel();
    if (SeedSmartView.emit == onEvent) SeedSmartView.emit = null;
    super.onClose();
  }

  DateTime? _pausedAt;

  /// Back in front after a while: one full read of what is open.
  static const _longPause = Duration(seconds: 30);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = _now();
    } else if (state == AppLifecycleState.resumed) {
      final at = _pausedAt;
      _pausedAt = null;
      if (at != null && _now().difference(at) >= _longPause) _reconnected();
    }
  }

  /// Another person or organisation: nothing of the last one stays and every
  /// read in flight is dropped when it lands.
  void _reset() {
    _epoch++;
    _sources = null;
    _sourcesLoading = null;
    sourceReads = 0;
    _starts.clear();
    _lastStart = null;
    _dirtyIds.clear();
    _removed.clear();
    _needsNewest.clear();
    _needsFull.clear();
    _flushing.clear();
    _debounceGen++;
    liveMode = null;
    for (final t in _tables) {
      t.loadId++;
      t.rows.clear();
      t.phase.value = SvPhase.loading;
    }
  }

  // ---- the gate --------------------------------------------------------------

  /// One command through the same gate as every Smart View read (saved
  /// views ride on it).
  Future<Map<String, dynamic>> gated(String cmd, Map<String, dynamic> args) =>
      _call(cmd, args);

  Future<Map<String, dynamic>> _call(String cmd, Map<String, dynamic> args) {
    final epoch = _epoch;
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return prev.then((_) async {
      try {
        return await _run(cmd, args, epoch);
      } finally {
        done.complete();
      }
    });
  }

  Future<Map<String, dynamic>> _run(
    String cmd,
    Map<String, dynamic> args,
    int epoch,
  ) async {
    for (var attempt = 0; ; attempt++) {
      await _waitSlot(epoch);
      if (epoch != _epoch) throw const SocketCallError('stale');
      if (!isOnline) throw const SocketCallError('not_connected');
      final at = _now();
      _starts.add(at);
      _lastStart = at;
      sent++;
      try {
        final reply = SeedSmartView.isActive
            ? await SeedSmartView.answer(cmd, args)
            : await _socket.sdCall(
                cmd,
                args,
                timeout: const Duration(seconds: 30),
              );
        if (epoch != _epoch) throw const SocketCallError('stale');
        _logCall(cmd, args, reply: reply);
        return reply;
      } on SocketCallError catch (e) {
        _logCall(cmd, args, error: e.code);
        if (SvLimits.retryable.contains(e.code) &&
            attempt < SvLimits.maxRetries) {
          await _delay(Duration(seconds: attempt + 1));
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _waitSlot(int epoch) async {
    while (true) {
      final now = _now();
      _starts.removeWhere((t) => now.difference(t) >= SvLimits.window);
      if (_starts.length >= SvLimits.budget) {
        await _delay(SvLimits.window - now.difference(_starts.first));
        continue;
      }
      final last = _lastStart;
      if (last != null && now.difference(last) < _gap) {
        await _delay(_gap - now.difference(last));
        continue;
      }
      return;
    }
  }

  /// Ids and counts only: never a value, a caption or a name.
  void _logCall(
    String cmd,
    Map<String, dynamic> args, {
    Map<String, dynamic>? reply,
    String? error,
  }) {
    final asked = [
      'smartview cmd=$cmd',
      if (args['tstruct'] != null) 'struct=${args['tstruct']}',
      if (args['as'] != null) 'as=${args['as']}',
      if (args['id'] != null) 'id=${args['id']}',
      if (args['offset'] != null) 'offset=${args['offset']}',
    ].join(' ');
    if (error != null) {
      RecordsLog.line('$asked -> ERROR $error');
      return;
    }
    final subs = reply?['submissions'];
    final forms = reply?['forms'];
    RecordsLog.line(
      '$asked -> ok'
      '${subs is List ? ' rows=${subs.length}' : ''}'
      '${forms is List ? ' forms=${forms.length}' : ''}'
      '${reply?['hasMore'] == null ? '' : ' hasMore=${reply?['hasMore']}'}',
    );
  }

  // ---- the source list -------------------------------------------------------

  /// The sources this person may open as a table, as the server listed them
  /// (hidden fields left out). Read once, kept until the organisation changes
  /// or a structure changed; never per keystroke.
  Future<List<SvSource>> sources({bool isForced = false}) {
    final kept = _sources;
    if (kept != null && !isForced) return Future.value(kept);
    return _sourcesLoading ??= _readSources().whenComplete(
      () => _sourcesLoading = null,
    );
  }

  /// What is held now, without reading.
  List<SvSource>? get keptSources => _sources;

  Future<List<SvSource>> _readSources() async {
    final epoch = _epoch;
    final data = await _call(SvCmd.sources, {'what': 'forms'});
    final list = [
      if (data['forms'] is List)
        for (final f in data['forms'] as List) ?SvSource.tryParse(f),
    ];
    if (epoch == _epoch) {
      _sources = list;
      sourceReads++;
    }
    return list;
  }

  // ---- reading a table -------------------------------------------------------

  SvTable open(SvSource source) {
    final t = SvTable(source);
    _tables.add(t);
    return t;
  }

  void close(SvTable t) {
    t.loadId++;
    _tables.remove(t);
    _dirtyIds.remove(t);
    _removed.remove(t);
    _needsNewest.remove(t);
    _needsFull.remove(t);
    _flushing.remove(t);
  }

  /// A full read: the person's own records (`submissions.list`, 500 a page,
  /// at most 20 pages), then the records sent to me (`records.mine` with and
  /// involved, at most 3 pages of 200 each). Rows show page by page. A pull
  /// to refresh or a retry passes [isQuiet]: the rows stay until new ones land.
  Future<void> load(
    SvTable t, {
    bool isQuiet = false,
    bool isOwnOnly = false,
    int? maxPages,
  }) async {
    final id = ++t.loadId;
    final epoch = _epoch;
    bool isStale() => id != t.loadId || epoch != _epoch;
    t.isLoading = true;
    if (!isQuiet || t.rows.isEmpty) t.phase.value = SvPhase.loading;
    t.hasPartialError.value = false;
    t.isPaging.value = true;
    final own = <SvRow>[];
    try {
      var offset = 0;
      var pages = 0;
      var isFirst = true;
      final pageLimit = maxPages ?? SvLimits.rowsMaxPages;
      while (pages < pageLimit) {
        final Map<String, dynamic> data;
        try {
          data = await _call(SvCmd.rows, {
            'tstruct': t.source.name,
            'limit': SvLimits.rowsPageSize,
            'offset': offset,
            'fetch': true,
            'withDetails': true,
          });
        } on SocketCallError catch (e) {
          if (isStale()) return;
          if (isFirst) {
            _fail(t, e);
            return;
          }
          t.hasPartialError.value = true;
          break;
        }
        if (isStale()) return;
        final page = SvPage.parse(data, isReceived: false);
        own.addAll([for (final r in page.rows) _cut(t.source, r)]);
        t.total.value = page.total;
        _show(t, own);
        isFirst = false;
        pages++;
        offset += SvLimits.rowsPageSize;
        if (!page.hasMore || page.received == 0) break;
        if (pages >= SvLimits.rowsMaxPages) {
          t.isCapped.value = true;
          RecordsLog.line(
            'smartview struct=${t.source.name} stopped at the '
            '${SvLimits.rowsMaxPages}-page cap',
          );
        }
      }
      if (!isOwnOnly) {
        for (final as in const ['with', 'involved']) {
          if (isStale()) return;
          await _readMine(t, as, own, isStale);
        }
      }
      if (isStale()) return;
      _show(t, own, isDone: true);
    } finally {
      if (!isStale()) {
        t.isLoading = false;
        t.isPaging.value = false;
      }
    }
  }

  /// The Overview's read of one structure: the newest page of the person's
  /// own records (`submissions.list`, the web's `structureStats`), through
  /// the same gate as every other read. Nothing stays open afterwards.
  Future<SvOverviewRead> readForOverview(SvSource source) async {
    final t = open(source);
    try {
      await load(t, isOwnOnly: true, maxPages: 1);
      if (t.phase.value != SvPhase.ready && t.phase.value != SvPhase.empty) {
        return const SvOverviewRead(isOk: false);
      }
      return SvOverviewRead(
        isOk: true,
        rows: t.rows.toList(),
        total: t.total.value,
      );
    } finally {
      close(t);
    }
  }

  /// `records.mine` for one list: pages continue at `offset + received`
  /// (`next` is always null here), only this structure's rows are kept, rows
  /// the table already holds are not replaced. A failure leaves the table as
  /// it was.
  Future<void> _readMine(
    SvTable t,
    String as,
    List<SvRow> own,
    bool Function() isStale,
  ) async {
    var offset = 0;
    for (var pages = 0; pages < SvLimits.mineMaxPages; pages++) {
      final Map<String, dynamic> data;
      try {
        data = await _call(SvCmd.mine, {
          'as': as,
          'limit': RecordLimits.mineLimit(as, RecordLimits.mineMaxLimit),
          if (offset > 0) 'offset': offset,
        });
      } on SocketCallError {
        return;
      }
      if (isStale()) return;
      final page = SvPage.parse(data, isReceived: true);
      final have = {for (final r in own) r.id};
      for (final r in page.rows) {
        if (r.tstruct.toLowerCase() != t.source.name.toLowerCase()) continue;
        if (have.add(r.id)) own.add(_cut(t.source, r));
      }
      _show(t, own);
      offset += page.received;
      if (!page.hasMore || page.received == 0) return;
      if (pages == SvLimits.mineMaxPages - 1) {
        RecordsLog.line(
          'smartview struct=${t.source.name} records.mine as=$as stopped at '
          'the ${SvLimits.mineMaxPages}-page cap',
        );
      }
    }
  }

  /// Hidden fields: only keys of the source list are kept.
  SvRow _cut(SvSource s, SvRow r) {
    final names = {for (final f in s.fields) f.name};
    return SvRow(
      id: r.id,
      tstruct: r.tstruct,
      by: r.by,
      byName: r.byName,
      ts: r.ts,
      recordStatus: r.recordStatus,
      holder: r.holder,
      claimants: r.claimants,
      completion: r.completion,
      values: {
        for (final e in r.values.entries)
          if (names.contains(e.key)) e.key: e.value,
      },
      labels: {
        for (final e in r.labels.entries)
          if (names.contains(e.key)) e.key: e.value,
      },
      files: {
        for (final e in r.files.entries)
          if (names.contains(e.key)) e.key: e.value,
      },
      canEdit: r.canEdit,
      isReceived: r.isReceived,
    );
  }

  /// Puts [rows] (newest first) on screen. Nothing at all is "empty" only
  /// once every list was read, so a structure that holds only received
  /// records does not flash the empty state.
  void _show(SvTable t, List<SvRow> rows, {bool isDone = false}) {
    final sorted = [...rows]..sort((a, b) => b.ts.compareTo(a.ts));
    t.rows.assignAll(sorted);
    _remember(t, sorted);
    if (sorted.isNotEmpty) {
      t.phase.value = SvPhase.ready;
    } else if (isDone) {
      t.phase.value = SvPhase.empty;
    }
  }

  /// The cards follow the record state (`liveOf`) like every other record
  /// card; nothing is read for them.
  void _remember(SvTable t, List<SvRow> rows) {
    if (!t.source.hasStatus) return;
    _tickets.rememberRows([for (final r in rows) r.toTicket(t.source)]);
  }

  void _fail(SvTable t, SocketCallError e) {
    t.errorMessage.value = e.message;
    if (t.rows.isNotEmpty) {
      t.hasPartialError.value = true;
      t.phase.value = SvPhase.ready;
      return;
    }
    t.phase.value = switch (e.code) {
      'not_found' => SvPhase.noAccess,
      _ when e.isConnectionGap => SvPhase.offline,
      _ => SvPhase.error,
    };
  }

  // ---- live ---------------------------------------------------------------------

  bool _isMine(SvTable t, Map data) {
    final s = idText(data['tstruct']);
    return s.isEmpty || s.toLowerCase() == t.source.name.toLowerCase();
  }

  /// Public so the debug page and tests can feed it events.
  void onEvent(Map<String, dynamic> e) {
    final name = e['type'] == 'sd_event' ? idText(e['event']) : e['type'];
    if (name == SvEvents.resync) {
      _reconnected();
      return;
    }
    final raw = e['data'];
    final data = raw is Map ? raw : e;
    if (name == SvEvents.structures) {
      _sources = null;
      final changed = idText(data['name']).toLowerCase();
      for (final t in _tables) {
        if (changed.isEmpty || changed == t.source.name.toLowerCase()) {
          _needsFull.add(t);
        }
      }
      _scheduleFlush();
      return;
    }
    if (!SvEvents.record.contains(name) || _tables.isEmpty) return;
    liveMode ??= () {
      final mode = data['record'] is Map ? 'record' : 'refetch';
      RecordsLog.line('smartview live mode=$mode (first event: $name)');
      return mode;
    }();
    final id = idNumber(data['id']);
    for (final t in _tables) {
      if (!_isMine(t, data)) continue;
      if (id == null) {
        _needsNewest.add(t);
        continue;
      }
      final action = idText(data['action']).toLowerCase();
      if (action == 'deleted') {
        t.rows.removeWhere((r) => r.id == id);
        if (t.rows.isEmpty && !t.isLoading) t.phase.value = SvPhase.empty;
        continue;
      }
      final record = data['record'];
      final held = t.rowOf(id);
      if (record is Map && held != null) {
        _patch(t, held, record.cast<String, dynamic>());
        continue;
      }
      (_dirtyIds[t] ??= {}).add(id);
    }
    _scheduleFlush();
  }

  /// `data.record` = `{by, claimants, completion, final, holder, status,
  /// ts}`: the row's status value, holder, claimants and completion change in
  /// place; no command.
  void _patch(SvTable t, SvRow row, Map<String, dynamic> r) {
    final field = t.source.table?.field;
    final status = idText(r['status']);
    final next = row.copyWith(
      holder: idText(r['holder']),
      claimants: [
        if (r['claimants'] is List)
          for (final c in r['claimants'] as List)
            if (idText(c).isNotEmpty) idText(c),
      ],
      completion: r['completion'] == null
          ? row.completion
          : intOf(r['completion']).clamp(0, 100),
      values: field != null && status.isNotEmpty
          ? {...row.values, field: status}
          : null,
    );
    _replace(t, next);
    final live = _tickets.liveOf(row.id);
    _tickets.setLiveFromEvent(
      row.id,
      live.value.copyWith(
        status: status.isEmpty ? null : status,
        holder: next.holder,
        claimants: next.claimants,
        completion: next.completion,
        isFinal: r['final'] == true,
        isStale: false,
      ),
    );
  }

  void _replace(SvTable t, SvRow next) {
    final i = t.rows.indexWhere((r) => r.id == next.id);
    if (i < 0) {
      t.rows.insert(0, next);
    } else {
      t.rows[i] = next;
    }
    t.versions[next.id] = (t.versions[next.id] ?? 0) + 1;
    if (t.phase.value == SvPhase.empty) t.phase.value = SvPhase.ready;
  }

  void _scheduleFlush() {
    final gen = ++_debounceGen;
    fireAndLog('smart_view_repository', () => _delay(_debounce).then((_) {
        if (gen == _debounceGen) _flushAll();
      }));
  }

  void _flushAll() {
    final all = {
      ..._dirtyIds.keys,
      ..._needsNewest,
      ..._needsFull,
    }.where(_tables.contains).toList();
    for (final t in all) {
      if (_flushing.add(t)) fireAndLog('smart_view_repository', () => _flush(t));
    }
  }

  /// One refresh in flight per table. Whatever came in meanwhile is read in
  /// the next round: only the affected records, never the whole table, unless
  /// a structure changed.
  Future<void> _flush(SvTable t) async {
    try {
      while (_tables.contains(t)) {
        final full = _needsFull.remove(t);
        final newest = _needsNewest.remove(t);
        final ids = _dirtyIds.remove(t) ?? <int>{};
        if (!full && !newest && ids.isEmpty) return;
        if (full) {
          await load(t, isQuiet: true);
          continue;
        }
        final epoch = _epoch;
        if (newest) await _readNewest(t);
        for (final id in ids) {
          if (epoch != _epoch) return;
          await _readOne(t, id);
        }
      }
    } finally {
      _flushing.remove(t);
    }
  }

  Future<void> _readOne(SvTable t, int id) async {
    try {
      final data = await _call(SvCmd.one, {'id': id});
      final raw = data['submission'];
      final row = SvRow.tryParse(raw, isReceived: false);
      if (row == null || !_tables.contains(t)) return;
      if (row.tstruct.isNotEmpty &&
          row.tstruct.toLowerCase() != t.source.name.toLowerCase()) {
        return;
      }
      final held = t.rowOf(id);
      final isMine = row.by.toLowerCase() == me;
      final next = _cut(
        t.source,
        SvRow(
          id: row.id,
          tstruct: row.tstruct,
          by: row.by,
          byName: held?.byName ?? row.byName,
          ts: row.ts,
          recordStatus: row.recordStatus,
          holder: row.holder,
          claimants: row.claimants,
          completion: row.completion,
          values: row.values,
          labels: held?.labels ?? const {},
          files: held?.files ?? const {},
          canEdit: held?.canEdit ?? false,
          isReceived: held?.isReceived ?? !isMine,
        ),
      );
      _replace(t, next);
      if (t.source.hasStatus) {
        _tickets.rememberRows([next.toTicket(t.source)]);
      }
    } on SocketCallError catch (e) {
      if (e.code == 'not_found') {
        t.rows.removeWhere((r) => r.id == id);
        if (t.rows.isEmpty) t.phase.value = SvPhase.empty;
      }
    }
  }

  /// A record with no id in its event, or a new one: page 1 only (50 rows)
  /// merged by id.
  Future<void> _readNewest(SvTable t) async {
    try {
      final data = await _call(SvCmd.rows, {
        'tstruct': t.source.name,
        'limit': 50,
        'offset': 0,
        'fetch': true,
        'withDetails': true,
      });
      final page = SvPage.parse(data, isReceived: false);
      for (final r in page.rows) {
        final held = t.rowOf(r.id);
        if (held == null || _differs(held, r)) _replace(t, _cut(t.source, r));
      }
      if (t.source.hasStatus) {
        _tickets.rememberRows([for (final r in t.rows) r.toTicket(t.source)]);
      }
    } on SocketCallError {
      return;
    }
  }

  bool _differs(SvRow a, SvRow b) =>
      a.ts != b.ts ||
      a.holder != b.holder ||
      a.completion != b.completion ||
      a.values.toString() != b.values.toString();

  /// Reconnect or the app back in front: every open table is read again, once.
  void _reconnected() {
    if (_tables.isEmpty) return;
    _needsFull.addAll(_tables);
    _sources = null;
    _scheduleFlush();
  }

  /// The choices after `#view `: from the source list held (read once).
  Future<List<CommandSuggestion>> suggestions(String typed) async {
    final all = await sources();
    return [
      for (final s in SvSources.suggest(all, typed))
        CommandSuggestion(
          value: s.name,
          label: s.caption,
          hint: '${s.hint} · ${s.fields.length} fields',
        ),
    ];
  }

  /// After a record was added from here: the newest page, one command, a
  /// moment later (the save goes through the outbox first).
  Future<void> refreshNewest(
    SvTable t, {
    Duration after = const Duration(milliseconds: 1500),
  }) async {
    await _delay(after);
    if (!_tables.contains(t)) return;
    await _readNewest(t);
  }

  /// A person-requested refresh: pull to refresh or Retry.
  Future<void> refresh(SvTable t) async {
    if (_flushing.contains(t)) return;
    _flushing.add(t);
    try {
      await load(t, isQuiet: true);
    } finally {
      _flushing.remove(t);
    }
  }
}
