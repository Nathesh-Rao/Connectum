import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/crash/crash_service.dart';

import '../../core/debug/records_log.dart';
import '../models/ticket.dart';
import '../records/paged_read.dart';
import '../records/record_commands.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'ticket_repository.dart';

/// The records that were SENT to this person, for My Work Space, inside the
/// organisation of the session. The workspace is not a server object: it is
/// built on the device from `submissions.list` (the records I made, read by
/// [syncOwn]), `records.mine as=involved` and `as=with` (what was sent to me),
/// the same as the web (`useWorkspaceSubmissions.js`). Another person's or
/// organisation's records never stay: ids are per organisation.
///
/// Reads are one at a time, pages one after the other, at least [minGap]
/// apart (a read is several commands, the server allows 30 per 10 s), and a
/// failed read keeps what was shown and says so ([hasError]); it is never an
/// empty list.
class WorkspaceRepository extends GetxService with WidgetsBindingObserver {
  WorkspaceRepository(
    this._socket,
    this._store,
    this._tickets, {
    required this.syncOwn,
    this.debounce = const Duration(seconds: 1),
    this.minGap = const Duration(seconds: 6),
    this.pageGap = const Duration(milliseconds: 350),
  });

  final SocketService _socket;
  final SessionStore _store;
  final TicketRepository _tickets;

  /// Reads my own records (`submissions.list`) into the cache; false when it
  /// failed.
  final Future<bool> Function() syncOwn;

  final Duration debounce;
  final Duration minGap;
  final Duration pageGap;

  static const pageSize = 100;

  /// 1000 records per list, the web's limit; reaching it is logged.
  static const maxPages = 10;

  /// Received records, newest first by when they came (`editedTs`, else
  /// `ts`).
  final received = <Ticket>[].obs;

  /// A read finished for this organisation (so "nothing yet" is true).
  final isLoaded = false.obs;

  /// The last read failed. What was shown stays; the screen says so.
  final hasError = false.obs;

  /// Counts finished reads, so a screen can react to a failure that follows
  /// a failure.
  final reads = 0.obs;

  /// A read is running or waiting.
  final isSyncing = false.obs;

  int syncs = 0;
  Timer? _timer;
  bool _isRunning = false;
  bool _wantsAgain = false;
  DateTime? _lastRead;
  StreamSubscription<Map<String, dynamic>>? _events;
  StreamSubscription<void>? _online;
  String? _key;

  String get _scope => '${_store.orgId}/${_store.userId}';

  String get _me => _tickets.me;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _key = _scope;
    _events = _socket.events.listen(onEvent);
    _online = _socket.onOnline.listen((_) => request());
    ever(_store.current, (_) => _reset());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _events?.cancel();
    _online?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) request();
  }

  static const _watched = {
    RecordEvents.changed,
    RecordEvents.assigned,
    RecordEvents.feedItem,
  };

  /// `submissions_changed`, `ticket_assigned` and feed events read the lists
  /// again (debounced, never more often than [minGap]). Public for tests.
  void onEvent(Map<String, dynamic> e) {
    final name = e['type'] == 'sd_event' ? e['event'] : e['type'];
    if (_watched.contains(name)) request();
  }

  /// Another person or organisation: nothing of the last one stays on screen
  /// and a read of the last one is dropped.
  void _reset() {
    if (_key == _scope) return;
    _timer?.cancel();
    _timer = null;
    _wantsAgain = false;
    _key = _scope;
    received.clear();
    isLoaded.value = false;
    hasError.value = false;
    if (_store.hasEnterpriseSession) request();
  }

  /// Asks for a read. A burst of asks becomes one read: the first waits
  /// [debounce], and a read is never started less than [minGap] after the
  /// last one ended. [now] skips both waits (the screen's own retry and
  /// pull to refresh).
  void request({bool now = false}) {
    if (!_store.hasEnterpriseSession) return;
    if (_isRunning) {
      _wantsAgain = true;
      return;
    }
    if (_timer != null && !now) return;
    _timer?.cancel();
    var wait = now ? Duration.zero : debounce;
    final last = _lastRead;
    if (!now && last != null) {
      final left = minGap - DateTime.now().difference(last);
      if (left > wait) wait = left;
    }
    isSyncing.value = true;
    _timer = Timer(wait, () {
      _timer = null;
      unawaited(syncNow());
    });
  }

  /// One read now (tests and the pull to refresh wait for it). A call while
  /// one runs asks for one more after it, through [request], so the gap
  /// between reads still holds.
  Future<void> syncNow() async {
    if (_isRunning) {
      _wantsAgain = true;
      return;
    }
    _isRunning = true;
    isSyncing.value = true;
    try {
      await _read();
    } finally {
      _isRunning = false;
      _lastRead = DateTime.now();
      isSyncing.value = _timer != null;
      if (_wantsAgain) {
        _wantsAgain = false;
        request();
      }
    }
  }

  Future<void> _read() async {
    final key = _scope;
    if (!_store.hasEnterpriseSession || _me.isEmpty) return;
    syncs++;
    RecordsLog.line('workspace read org=${_store.orgId} user=${_store.userId}');
    var isOk = true;
    try {
      isOk = await syncOwn();
    } on Object catch (e, s) {
      CrashService.nonFatal(e, s);
      RecordsLog.line('workspace own records failed: $e');
      isOk = false;
    }
    if (key != _scope) return;
    final involved = await _list('involved', key);
    if (involved == null) {
      isOk = false;
    }
    final withMe = involved == null ? null : await _list('with', key);
    if (withMe == null) isOk = false;
    if (key != _scope) return;
    if (involved != null && withMe != null) {
      received.assignAll(_merge(involved, withMe));
    }
    isLoaded.value = isOk || isLoaded.value;
    hasError.value = !isOk;
    reads.value++;
    RecordsLog.line(
      'workspace done own+received org=${_store.orgId} '
      'received=${received.length} ok=$isOk',
    );
  }

  /// One list, every page; null when a page failed (the caller keeps what it
  /// had).
  Future<List<Ticket>?> _list(String as, String key) async {
    final rows = <Ticket>[];
    final result = await PagedRead.run(
      label: 'records.mine as=$as',
      maxPages: maxPages,
      gap: pageGap,
      isStale: () => key != _scope,
      page: (offset) async {
        final TicketPage got;
        try {
          got = await _tickets.mine(as: as, offset: offset);
        } on SocketCallError {
          rethrow;
        } on Object catch (e) {
          throw SocketCallError('error', '$e');
        }
        rows.addAll(got.tickets);
        return (received: got.received, hasMore: got.hasMore);
      },
    );
    return result.isOk ? rows : null;
  }

  /// Involved first, then with; not mine, not waiting for approval, once per
  /// record id; newest first by when they came to me.
  List<Ticket> _merge(List<Ticket> involved, List<Ticket> withMe) {
    final seen = <int>{};
    final out = <Ticket>[];
    for (final t in [...involved, ...withMe]) {
      if (t.by.toLowerCase() == _me || t.isAwaitingApproval) continue;
      if (seen.add(t.id)) out.add(t);
    }
    out.sort((a, b) => _at(b).compareTo(_at(a)));
    return out;
  }

  int _at(Ticket t) => t.editedTs > 0 ? t.editedTs : t.ts;
}
