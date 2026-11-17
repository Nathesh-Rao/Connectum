import 'dart:async';

import '../socket/socket_service.dart';

/// The one queue that reads `record.actions` for cards on screen. Cards only
/// say "I am on screen" ([show]) and "I am gone" ([hide]); this class decides
/// when a command goes out: one at a time, [spacing] apart, at most [budget]
/// in any [window] (the server's limit is 30 per 10 s per connection and
/// other traffic needs room), newest record first, never for a record whose
/// last read is fresh, backing off when the server says it is busy.
///
/// A future batch command replaces [fetch] only; nothing else changes.
class RecordActionsQueue {
  RecordActionsQueue({
    required this.fetch,
    required this.isFresh,
    required this.canRun,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  static const spacing = Duration(milliseconds: 300);
  static const budget = 8;
  static const window = Duration(seconds: 10);
  static const maxAttempts = 5;
  static const _backoffBase = Duration(seconds: 1);
  static const _backoffCap = Duration(seconds: 20);
  static const retryable = {'rate_limited', 'busy', 'timeout'};

  /// Reads one record. Throws [SocketCallError] only for a retryable refusal;
  /// any other outcome is settled by the caller (and counts as read).
  final Future<void> Function(int id) fetch;

  /// The record's last read is younger than the cache time.
  final bool Function(int id) isFresh;

  /// The connection is up (or a demo answers).
  final bool Function() canRun;

  /// Record id -> how many cards of it are on screen.
  final _visible = <int, int>{};
  final _pending = <int>{};
  final _attempts = <int, int>{};
  final _starts = <DateTime>[];
  DateTime? _lastEnd;
  DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _timer;
  bool _isRunning = false;
  bool _isPaused = false;
  bool _isClosed = false;
  bool _isKickQueued = false;

  /// Commands sent so far (tests and the debug line).
  int sent = 0;

  bool isVisible(int id) => _visible.containsKey(id);
  bool isQueued(int id) => _pending.contains(id);
  int get pendingCount => _pending.length;

  /// Record [id] is on screen: read it unless a fresh read exists.
  void show(int id) {
    final count = _visible[id] ?? 0;
    if (count == 0) _attempts.remove(id);
    _visible[id] = count + 1;
    if (!isFresh(id)) _pending.add(id);
    _kick();
  }

  /// Record [id] scrolled away or its screen is covered: an entry not yet
  /// sent is dropped.
  void hide(int id) {
    final count = (_visible[id] ?? 0) - 1;
    if (count > 0) {
      _visible[id] = count;
      return;
    }
    _visible.remove(id);
    _pending.remove(id);
    _attempts.remove(id);
    if (_pending.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// The record changed (an event, a reconnect): read it again if it is on
  /// screen; a record off screen is only left without a fresh read.
  void markStale(int id) {
    if (!_visible.containsKey(id)) return;
    _pending.add(id);
    _kick();
  }

  void markAllStale() {
    _pending.addAll(_visible.keys);
    _kick();
  }

  /// Starts the pump after the cards built in this frame have all said so,
  /// so the newest of them goes first.
  void _kick() {
    if (_isKickQueued) return;
    _isKickQueued = true;
    scheduleMicrotask(() {
      _isKickQueued = false;
      _pump();
    });
  }

  /// The app went to the background (or the connection dropped).
  void pause() {
    _isPaused = true;
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    _isPaused = false;
    _kick();
  }

  /// Another person or organisation: nothing stays.
  void clear() {
    _timer?.cancel();
    _timer = null;
    _visible.clear();
    _pending.clear();
    _attempts.clear();
    _starts.clear();
  }

  void dispose() {
    _isClosed = true;
    clear();
  }

  Duration _waitFor(DateTime now) {
    var at = _blockedUntil;
    final end = _lastEnd;
    if (end != null && end.add(spacing).isAfter(at)) at = end.add(spacing);
    _starts.removeWhere((t) => now.difference(t) >= window);
    if (_starts.length >= budget) {
      final free = _starts.first.add(window);
      if (free.isAfter(at)) at = free;
    }
    final wait = at.difference(now);
    return wait.isNegative ? Duration.zero : wait;
  }

  void _pump() {
    if (_isClosed || _isRunning || _isPaused || _timer != null) return;
    if (_pending.isEmpty || !canRun()) return;
    final wait = _waitFor(_now());
    if (wait > Duration.zero) {
      _timer = Timer(wait, () {
        _timer = null;
        _pump();
      });
      return;
    }
    _run();
  }

  int? _next() {
    // Newest record first: ids grow with time, and the newest cards sit
    // nearest the bottom of a chat, where it opens.
    while (_pending.isNotEmpty) {
      final id = _pending.reduce((a, b) => a > b ? a : b);
      _pending.remove(id);
      if (_visible.containsKey(id) && !isFresh(id)) return id;
    }
    return null;
  }

  Future<void> _run() async {
    final id = _next();
    if (id == null) return;
    _isRunning = true;
    final now = _now();
    _starts.add(now);
    sent++;
    try {
      await fetch(id);
      _attempts.remove(id);
    } on SocketCallError catch (e) {
      if (retryable.contains(e.code)) _retry(id);
    } catch (_) {
      // The fetch settles its own failures; nothing is retried here.
    } finally {
      _isRunning = false;
      _lastEnd = _now();
    }
    _pump();
  }

  void _retry(int id) {
    final n = (_attempts[id] ?? 0) + 1;
    _attempts[id] = n;
    var delay = _backoffBase * (1 << (n - 1));
    if (delay > _backoffCap) delay = _backoffCap;
    final until = _now().add(delay);
    if (until.isAfter(_blockedUntil)) _blockedUntil = until;
    if (n < maxAttempts && _visible.containsKey(id)) _pending.add(id);
  }
}
