import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_tasks.dart';
import '../models/approval.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'feed_repository.dart';

/// A `request_created` or `request_resolved` event.
class ApprovalChange {
  const ApprovalChange(this.request, {required this.isCreated});

  final Approval request;
  final bool isCreated;
}

/// The `req.*` calls and events. `req.respond` takes no `cid`, so an answer
/// is sent once and never replayed by the app: a failure goes back to the
/// person. The screen owns its lists and reads again when [refreshes] fires.
class ApprovalRepository extends GetxService with WidgetsBindingObserver {
  ApprovalRepository(this._socket, this._store, this._feed);

  final SocketService _socket;
  final SessionStore _store;
  final FeedRepository _feed;

  static const pageSize = 50;
  static const burst = Duration(milliseconds: 150);

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
    _events = _socket.events.listen(onEvent);
    _online = _socket.onOnline.listen((_) => scheduleRefresh());
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _burst?.cancel();
    _events?.cancel();
    _online?.cancel();
    _changes.close();
    _refreshes.close();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) scheduleRefresh();
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
    final data = await _socket.sdCall('req.list', {
      'status': status,
      'limit': pageSize,
      if (offset > 0) 'offset': offset,
    });
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
    _feed.scheduleRefresh();
    return answered;
  }
}
