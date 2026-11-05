import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../features/notifications/models/feed_item.dart';
import '../../features/notifications/models/feed_reducer.dart';
import '../e2e/e2e_models.dart';
import '../models/ids.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'e2e_repository.dart';

/// The workspace feed (`feed.*`): the items, the counts behind the bell, and
/// the three live events. In memory only: the server is the source, and
/// events sent while the app was offline are lost and `feed.list` has no
/// "since" cursor, so every (re)connect and every resume reads the summary and
/// the latest [firstReadSize] items and replaces the local list with them.
/// A line for the in-app notice; [taskId] when it is about one task.
class FeedNotice {
  const FeedNotice(this.line, {this.taskId, this.ticketId, this.tstruct});

  final String line;
  final int? taskId;

  /// A ticket is now with the person (`ticket_assigned`).
  final int? ticketId;
  final String? tstruct;
}

class FeedRepository extends GetxService with WidgetsBindingObserver {
  FeedRepository(this._socket, this._store, this._e2e);

  final SocketService _socket;
  final SessionStore _store;
  final E2eRepository _e2e;

  static const pageSize = 50;
  static const firstReadSize = 200;
  static const burst = Duration(milliseconds: 150);
  static const _quiet = {
    'request_created',
    'request_resolved',
    'task_assigned',
    'task_updated',
    'ticket_assigned',
    'submission_approved',
    'submission_rejected',
    'submission_notice',
    'broadcast',
  };

  final items = <FeedItem>[].obs;
  final counts = FeedCounts.zero.obs;
  final unread = 0.obs;

  /// The first read of this session has not answered yet.
  final isLoading = true.obs;
  final hasError = false.obs;

  final _itemController = StreamController<FeedItem>.broadcast();
  final _goneController = StreamController<List<String>>.broadcast();
  final _noticeController = StreamController<FeedNotice>.broadcast();

  /// A `feed_item` event: new, or changed (a coalesced count, re-opened).
  Stream<FeedItem> get onItem => _itemController.stream;

  /// Ids that no longer need a notification: removed, read or resolved.
  Stream<List<String>> get onGone => _goneController.stream;

  /// A short line for the in-app notice of the events that only refresh.
  Stream<FeedNotice> get onNotice => _noticeController.stream;

  final _hasMore = <String, bool>{};
  final _loaded = <String>{};
  final _readTexts = <String, String>{};
  Timer? _burst;
  Future<void>? _refreshing;
  StreamSubscription<Map<String, dynamic>>? _events;
  StreamSubscription<void>? _online;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _events = _socket.events.listen(onEvent);
    _online = _socket.onOnline.listen((_) => scheduleRefresh());
    ever(_store.current, (_) => _reset());
    ever(counts, (c) => unread.value = c.unread);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _burst?.cancel();
    _events?.cancel();
    _online?.cancel();
    _itemController.close();
    _goneController.close();
    _noticeController.close();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) scheduleRefresh();
  }

  void _reset() {
    _burst?.cancel();
    items.clear();
    counts.value = FeedCounts.zero;
    isLoading.value = true;
    hasError.value = false;
    _hasMore.clear();
    _loaded.clear();
    _readTexts.clear();
  }

  static String _key(String priority, bool isUnreadOnly) =>
      '$priority|$isUnreadOnly';

  bool hasMore(String priority, bool isUnreadOnly) =>
      _hasMore[_key(priority, isUnreadOnly)] ?? false;

  /// Bursts of events become one read.
  void scheduleRefresh() {
    _burst?.cancel();
    _burst = Timer(burst, () => unawaited(refresh()));
  }

  /// The summary and the latest [firstReadSize] items, replacing the local
  /// list: reads, resolves, dismissals and removals done elsewhere show only
  /// this way. Older items load by paging.
  Future<void> refresh() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    if (!_socket.isOnline || _store.current.value == null) {
      isLoading.value = false;
      return;
    }
    try {
      final summary = await _socket.sdCall('feed.summary', {});
      counts.value = FeedCounts.tryParse(summary) ?? counts.value;
      final page = await _fetch(
        priority: 'all',
        isUnreadOnly: false,
        limit: firstReadSize,
      );
      items.assignAll(FeedReducer.replace(page.items));
      _loaded
        ..clear()
        ..add(_key('all', false));
      _hasMore
        ..clear()
        ..[_key('all', false)] = page.hasMore;
      hasError.value = false;
    } on SocketCallError catch (_) {
      if (items.isEmpty) hasError.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  Future<({List<FeedItem> items, bool hasMore})> _fetch({
    required String priority,
    required bool isUnreadOnly,
    FeedItem? after,
    int limit = pageSize,
  }) async {
    final data = await _socket.sdCall('feed.list', {
      'priority': priority,
      if (isUnreadOnly) 'unreadOnly': true,
      'limit': limit,
      if (after != null) ...{'before': after.ts, 'beforeId': after.id},
    });
    counts.value = FeedCounts.tryParse(data['counts']) ?? counts.value;
    final raw = data['notifications'];
    final page = <FeedItem>[
      if (raw is List)
        for (final j in raw) ?FeedItem.tryParse(j),
    ];
    return (items: page, hasMore: data['hasMore'] == true);
  }

  /// The first page of a filter not read yet this session.
  Future<void> ensureFilter(String priority, bool isUnreadOnly) async {
    final key = _key(priority, isUnreadOnly);
    if (_loaded.contains(key)) return;
    final page = await _fetch(priority: priority, isUnreadOnly: isUnreadOnly);
    items.assignAll(FeedReducer.merge(items, page.items));
    _loaded.add(key);
    _hasMore[key] = page.hasMore;
  }

  /// The next page of a filter, after the oldest item shown for it.
  Future<void> loadMore(String priority, bool isUnreadOnly) async {
    final key = _key(priority, isUnreadOnly);
    if (_hasMore[key] != true) return;
    final shown = FeedReducer.filter(
      items,
      priority: priority,
      isUnreadOnly: isUnreadOnly,
    );
    final page = await _fetch(
      priority: priority,
      isUnreadOnly: isUnreadOnly,
      after: shown.isEmpty ? null : shown.last,
    );
    items.assignAll(FeedReducer.merge(items, page.items));
    _hasMore[key] = page.hasMore;
  }

  // ---- events --------------------------------------------------------------

  /// Public so the debug page and tests can feed it events.
  void onEvent(Map<String, dynamic> e) {
    if (e['type'] != 'sd_event') return;
    final event = e['event'];
    final data = (e['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (event) {
      case 'feed_item':
        final item = FeedItem.tryParse(data['notification']);
        _setCounts(data['counts']);
        if (item == null) {
          scheduleRefresh();
          return;
        }
        items.assignAll(FeedReducer.applyItem(items, item));
        _itemController.add(item);
        if (item.isRead || item.isResolved) _goneController.add([item.id]);
      case 'feed_removed':
        final ids = _ids(data['ids']);
        items.assignAll(FeedReducer.applyRemoved(items, ids));
        _setCounts(data['counts']);
        _goneController.add(ids);
      case 'feed_changed':
        final ids = _ids(data['ids']);
        final isRead = data['read'] != false;
        items.assignAll(FeedReducer.applyChanged(items, ids, isRead: isRead));
        _setCounts(data['counts']);
        if (isRead) _goneController.add(ids);
      case final String name when _quiet.contains(name):
        scheduleRefresh();
        final line = _noticeFor(name, data);
        if (line != null) {
          _noticeController.add(
            FeedNotice(
              line,
              taskId: _taskIdOf(name, data),
              ticketId: name == 'ticket_assigned' ? idNumber(data['id']) : null,
              tstruct: name == 'ticket_assigned'
                  ? idText(data['tstruct'])
                  : null,
            ),
          );
        }
    }
  }

  void _setCounts(Object? raw) {
    final parsed = FeedCounts.tryParse(raw);
    if (parsed != null) {
      counts.value = parsed;
    } else {
      scheduleRefresh();
    }
  }

  static List<String> _ids(Object? raw) => [
    if (raw is List)
      for (final id in raw) idText(id),
  ];

  /// The task of a `task_assigned` / `task_updated` event: `data.task.id`.
  static int? _taskIdOf(String event, Map<String, dynamic> data) {
    if (event != 'task_assigned' && event != 'task_updated') return null;
    final task = data['task'];
    return task is Map ? idNumber(task['id']) : null;
  }

  static String? _noticeFor(String event, Map<String, dynamic> data) {
    switch (event) {
      case 'task_assigned':
        return 'You have a new task.';
      case 'task_updated':
        return 'A task was updated.';
      case 'ticket_assigned':
        return data['action'] == 'Raised'
            ? 'A ticket was raised to you.'
            : 'A ticket is now with you.';
      case 'request_created':
        return 'You have a new request to review.';
      case 'broadcast':
        final text = idText(data['text']);
        return text.isEmpty ? null : FeedItem.clip('Announcement: $text', 120);
      default:
        return null;
    }
  }

  // ---- actions (optimistic, rolled back on an error) ------------------------

  Future<void> setRead(List<String> ids, {required bool isRead}) {
    final targets = ids.toSet();
    final delta = items
        .where((i) => targets.contains(i.id) && i.isRead != isRead)
        .length;
    return _optimistic(
      () {
        items.assignAll(FeedReducer.applyChanged(items, ids, isRead: isRead));
        _bumpUnread(isRead ? -delta : delta);
      },
      () async {
        final data = await _socket.sdCall('feed.read', {
          'ids': ids,
          if (!isRead) 'read': false,
        });
        _setCounts(data['counts']);
      },
    );
  }

  Future<void> markAllRead() => _optimistic(
    () {
      items.assignAll([for (final i in items) i.copyWith(isRead: true)]);
      counts.value = FeedCounts(
        high: counts.value.high,
        medium: counts.value.medium,
        low: counts.value.low,
        resolved: counts.value.resolved,
        unread: 0,
        total: counts.value.total,
      );
    },
    () async {
      final data = await _socket.sdCall('feed.read', {'all': true});
      _setCounts(data['counts']);
    },
  );

  Future<void> resolve(String id) => _optimistic(
    () => items.assignAll([
      for (final i in items)
        i.id == id
            ? i.copyWith(
                priority: 'resolved',
                isResolved: true,
                isRead: true,
                resolvedTs: DateTime.now().millisecondsSinceEpoch,
              )
            : i,
    ]),
    () async {
      final data = await _socket.sdCall('feed.resolve', {'id': id});
      final item = FeedItem.tryParse(data['notification']);
      if (item != null) items.assignAll(FeedReducer.applyItem(items, item));
      _setCounts(data['counts']);
      _goneController.add([id]);
    },
  );

  Future<void> resolveAll() => _optimistic(
    () {
      final now = DateTime.now().millisecondsSinceEpoch;
      items.assignAll([
        for (final i in items)
          i.isResolved
              ? i
              : i.copyWith(
                  priority: 'resolved',
                  isResolved: true,
                  isRead: true,
                  resolvedTs: now,
                ),
      ]);
      counts.value = FeedCounts(
        high: 0,
        medium: 0,
        low: 0,
        resolved:
            counts.value.resolved +
            counts.value.high +
            counts.value.medium +
            counts.value.low,
        unread: 0,
        total: counts.value.total,
      );
    },
    () async {
      final open = [
        for (final i in items)
          if (i.isResolved) i.id,
      ];
      final data = await _socket.sdCall('feed.resolve', {'all': true});
      _setCounts(data['counts']);
      _goneController.add(open);
    },
  );

  Future<void> dismiss(String id) => _optimistic(
    () => items.assignAll(FeedReducer.applyRemoved(items, [id])),
    () async {
      final data = await _socket.sdCall('feed.dismiss', {'id': id});
      _setCounts(data['counts']);
      _goneController.add([id]);
    },
  );

  Future<void> clearResolved() {
    final gone = [
      for (final i in items)
        if (i.isResolved) i.id,
    ];
    return _optimistic(
      () => items.assignAll(FeedReducer.applyRemoved(items, gone)),
      () async {
        final data = await _socket.sdCall('feed.clear', {});
        _setCounts(data['counts']);
        _goneController.add(gone);
      },
    );
  }

  void _bumpUnread(int delta) {
    final c = counts.value;
    counts.value = FeedCounts(
      high: c.high,
      medium: c.medium,
      low: c.low,
      resolved: c.resolved,
      unread: (c.unread + delta).clamp(0, 1 << 30),
      total: c.total,
    );
  }

  /// Shows the change at once; on an error puts the old state back and
  /// rethrows, so the caller can tell the person.
  Future<void> _optimistic(
    void Function() apply,
    Future<void> Function() send,
  ) async {
    final oldItems = items.toList();
    final oldCounts = counts.value;
    apply();
    try {
      await send();
    } catch (_) {
      items.assignAll(oldItems);
      counts.value = oldCounts;
      rethrow;
    }
  }

  // ---- text ----------------------------------------------------------------

  /// The words to show for [item]: its message, or for an end-to-end item the
  /// text opened on this device. Null when an encrypted item cannot be read
  /// (yet). Nothing here is logged or stored.
  Future<String?> readableText(FeedItem item) async {
    if (!item.isE2e) return item.message;
    final cached = _readTexts['${item.id}@${item.ts}'];
    if (cached != null) return cached;
    final conv = item.conversationId;
    if (conv == null || !item.message.startsWith('e2e1:')) return null;
    final reading = await _e2e.open(text: item.message, convId: conv);
    if (reading.state != E2eReadState.ok) return null;
    final text = reading.text ?? '';
    _readTexts['${item.id}@${item.ts}'] = text;
    return text;
  }
}
