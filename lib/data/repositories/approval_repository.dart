import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_tasks.dart';
import '../../core/log/app_log.dart';
import '../models/approval.dart';
import '../session_store.dart';
import '../socket/read_gate.dart';
import '../socket/socket_service.dart';
import 'feed_repository.dart';
import '../../core/log/safe.dart';

/// A `request_created` or `request_resolved` event.
class ApprovalChange {
  const ApprovalChange(this.request, {required this.isCreated});

  final Approval request;
  final bool isCreated;
}

/// The `req.*` calls and events, and the one list of requests the Inbox's
/// Approvals pane and its button read ([all], [count]). `req.respond` takes no
/// `cid`, so an answer is sent once and never replayed by the app: a failure
/// goes back to the person. Every `req.list` goes through the shared
/// [ReadGate]; a sequence number drops an answer that arrives after a newer
/// read, event or answer.
class ApprovalRepository extends GetxService with WidgetsBindingObserver {
  ApprovalRepository(this._socket, this._store, this._feed, {ReadGate? gate})
    : _gate = gate ?? ReadGate();

  final SocketService _socket;
  final SessionStore _store;
  final FeedRepository _feed;
  final ReadGate _gate;

  /// The server sends at most 200 a page, newest first.
  static const pageSize = 200;
  static const maxPages = 5;
  static const burst = Duration(milliseconds: 150);

  /// Every request read so far (any status), as the server listed them.
  final all = <Approval>[].obs;

  /// The requests the person's direct reports raised (`req.team`, read
  /// only), read only while [hasReports]. An error leaves it empty.
  final team = <Approval>[].obs;

  /// The person has direct reports (the Inbox's counts say so): `req.team`
  /// is read with every refresh. Set by the Inbox.
  final hasReports = false.obs;

  /// Requests waiting for the person: pending and `canRespond`. The ones the
  /// person sent are never counted.
  final count = 0.obs;

  /// A read has finished at least once for this session.
  final hasRead = false.obs;
  final isReading = false.obs;

  /// The last read failed; [all] is what was read before.
  final hasError = false.obs;

  /// The last read failed because the connection was down.
  final isOfflineError = false.obs;

  Stream<int> get counts => count.stream;

  bool _isStarted = false;
  int _seq = 0;
  int _teamSeq = 0;

  final _changes = StreamController<ApprovalChange>.broadcast();
  final _refreshes = StreamController<void>.broadcast();
  Timer? _burst;
  StreamSubscription<Map<String, dynamic>>? _events;
  StreamSubscription<void>? _online;

  Stream<ApprovalChange> get changes => _changes.stream;
  Stream<void> get refreshes => _refreshes.stream;

  String get me => (_store.userId ?? SeedTasks.me).toLowerCase();

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _events = _socket.events.listen(
      (event) => fireAndLog('approval_repository', () async => onEvent(event)),
      onError: streamOnError('approval_repository'),
    );
    _online = _socket.onOnline.listen(
      (_) => scheduleRefresh(),
      onError: streamOnError('approval_repository'),
    );
    _bursts = _refreshes.stream.listen((_) {
      if (_isStarted) fireAndLog('approval_repository', () => refresh());
    }, onError: streamOnError('approval_repository'));
  }

  StreamSubscription<void>? _bursts;

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _burst?.cancel();
    _events?.cancel();
    _online?.cancel();
    _bursts?.cancel();
    _changes.close();
    _refreshes.close();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) scheduleRefresh();
  }

  /// The Inbox was shown: from now on the list is kept up to date, and it is
  /// read once at once.
  Future<void> start() {
    if (_isStarted) return Future.value();
    _isStarted = true;
    return refresh();
  }

  /// The person changed: nothing of the last session stays.
  void reset() {
    _seq++;
    _teamSeq++;
    _isStarted = false;
    all.clear();
    team.clear();
    hasReports.value = false;
    count.value = 0;
    hasRead.value = false;
    isReading.value = false;
    hasError.value = false;
    isOfflineError.value = false;
  }

  /// Reads every request again (any status), a page at a time through the
  /// gate, at most [maxPages]. A failed read keeps [all]. False when it did
  /// not end in a new list (failed, or a newer read, event or answer came
  /// first).
  Future<bool> refresh() async {
    final seq = ++_seq;
    isReading.value = true;
    try {
      final rows = <Approval>[];
      final seen = <int>{};
      var offset = 0;
      for (var page = 0; page < maxPages; page++) {
        final read = await list(status: 'all', offset: offset);
        if (seq != _seq) return false;
        for (final r in read.requests) {
          if (seen.add(r.id)) rows.add(r);
        }
        offset += read.requests.length;
        if (!read.hasMore || read.requests.isEmpty) break;
      }
      all.assignAll(rows);
      _recount();
      hasRead.value = true;
      hasError.value = false;
      isOfflineError.value = false;
      await refreshTeam();
      return true;
    } on SocketCallError catch (e) {
      if (seq != _seq) return false;
      hasError.value = true;
      isOfflineError.value = e.isConnectionGap;
      return false;
    } finally {
      if (seq == _seq) isReading.value = false;
    }
  }

  /// Reads `req.team` (status all, 200 a page, at most [maxPages]) through
  /// the gate. A newer read drops this one when it lands. An error of any
  /// kind (an older server has no such call) is an empty team list, never a
  /// visible error. Not read at all without reports.
  Future<void> refreshTeam() async {
    final seq = ++_teamSeq;
    if (!hasReports.value) {
      team.clear();
      return;
    }
    final rows = <Approval>[];
    final seen = <int>{};
    try {
      var offset = 0;
      for (var page = 0; page < maxPages; page++) {
        final read = await listTeam(offset: offset);
        if (seq != _teamSeq) return;
        for (final r in read.requests) {
          if (seen.add(r.id)) rows.add(r.asTeam());
        }
        offset += read.requests.length;
        if (!read.hasMore || read.requests.isEmpty) break;
      }
    } on SocketCallError catch (e) {
      AppLog.w('approval_repository', 'req.team failed code=${e.code}');
      if (seq != _teamSeq) return;
      rows.clear();
    } catch (e, st) {
      AppLog.e('approval_repository', e, st, 'req.team unreadable');
      if (seq != _teamSeq) return;
      rows.clear();
    }
    team.assignAll(rows);
  }

  void _recount() {
    count.value = all.where((r) => r.isPending && r.canRespond).length;
  }

  /// A newer fact than any read in flight: that read is dropped.
  void _put(Approval request, {required bool isCreated}) {
    if (!hasRead.value) return;
    _seq++;
    isReading.value = false;
    final i = all.indexWhere((r) => r.id == request.id);
    if (i < 0) {
      if (isCreated) all.insert(0, request);
    } else if (!isCreated) {
      all[i] = all[i].copyWith(
        status: request.status,
        canRespond: false,
        resolvedTs: request.resolvedTs,
        resolvedBy: request.resolvedBy,
        resolvedByName: request.resolvedByName.isEmpty
            ? null
            : request.resolvedByName,
        resolvedByDesignation: request.resolvedByDesignation,
        reason: request.reason.isEmpty ? null : request.reason,
        returned: request.returned,
      );
    }
    _recount();
  }

  void scheduleRefresh() {
    _burst?.cancel();
    _burst = Timer(burst, () {
      if (!_refreshes.isClosed) _refreshes.add(null);
    });
  }

  /// Public so the debug page and tests can feed it events. The event's data
  /// is the request itself.
  void onEvent(Map<String, dynamic> e) {
    if (e['type'] != 'sd_event') return;
    final event = e['event'];
    if (event != 'request_created' && event != 'request_resolved') return;
    final data = e['data'];
    final raw = data is Map && data['request'] is Map ? data['request'] : data;
    final request = Approval.tryParse(raw, viewer: me);
    if (request != null) {
      _put(request, isCreated: event == 'request_created');
      _changes.add(
        ApprovalChange(request, isCreated: event == 'request_created'),
      );
    }
    _feed.scheduleRefresh();
    scheduleRefresh();
  }

  // ---- calls -----------------------------------------------------------------

  /// [status]: pending | accepted | rejected | ignored | all.
  Future<ApprovalPage> list({
    String status = Approval.pending,
    int offset = 0,
  }) async {
    if (SeedTasks.isActive) {
      return SeedTasks.requestPage(status, offset, pageSize);
    }
    final data = await _gate.run(
      () => _socket.sdCall('req.list', {
        'status': status,
        'limit': pageSize,
        if (offset > 0) 'offset': offset,
      }),
    );
    return ApprovalPage.parse(data);
  }

  /// One page of `req.team`: the requests the person's direct reports raised.
  Future<ApprovalPage> listTeam({int offset = 0}) async {
    final data = await _gate.run(
      () => _socket.sdCall('req.team', {
        'status': 'all',
        'limit': pageSize,
        if (offset > 0) 'offset': offset,
      }),
    );
    return ApprovalPage.parse(data);
  }

  /// [action]: accept | reject | return | ignore.
  Future<Approval> respond(
    int id,
    String action, {
    String? reason,
    String? comment,
    bool? allowResubmit,
  }) async {
    final Approval answered;
    if (SeedTasks.isActive) {
      SeedTasks.failIfAsked();
      final old = SeedTasks.requests.firstWhere((r) => r.id == id);
      answered = old.copyWith(
        status: switch (action) {
          'accept' => Approval.accepted,
          'ignore' => Approval.ignored,
          _ => Approval.rejected,
        },
        canRespond: false,
        resolvedTs: DateTime.now().millisecondsSinceEpoch,
        resolvedBy: SeedTasks.me,
        resolvedByName: 'Me',
        reason: reason,
      );
      SeedTasks.requests = [
        for (final r in SeedTasks.requests) r.id == id ? answered : r,
      ];
    } else {
      final data = await _socket.sdCall('req.respond', {
        'id': id,
        'action': action,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
        'allowResubmit': ?allowResubmit,
      });
      answered =
          Approval.tryParse(data['request'], viewer: me) ??
          (throw const SocketCallError('error', 'The server sent no request.'));
    }
    final done = action == 'return' && !answered.returned
        ? answered.copyWith(returned: true)
        : answered;
    _put(done, isCreated: false);
    _feed.scheduleRefresh();
    return done;
  }
}
