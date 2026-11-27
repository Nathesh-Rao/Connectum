import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/log/app_log.dart';
import '../../core/log/safe.dart';
import 'models/inbox_live_rule.dart';

/// Where the Inbox is, for the live re-read.
enum InboxLiveState {
  /// Not opened yet (its first read has not started) or signed out.
  closed,

  /// Opened, but the tab is not shown or the app is not in the foreground.
  hidden,

  /// Shown and in the foreground.
  active,
}

/// Turns the socket's events into quiet re-reads of the Inbox: a burst
/// becomes one read [debounce] after its last event, one read at a time, and
/// never less than [minGap] after the last one ended. While the Inbox is
/// hidden nothing is read; one read follows when it is shown again. It adds
/// no subscription of its own: the caller hands it the events and the
/// "connected again" signal that the app already has.
class InboxLive with WidgetsBindingObserver {
  InboxLive({
    required this.state,
    required this.isBusy,
    required this.read,
    this.debounce = const Duration(milliseconds: 300),
    this.minGap = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final InboxLiveState Function() state;

  /// A read the person asked for is running: the live read waits for it.
  final bool Function() isBusy;

  /// One re-read; returns when its answer was used or dropped. Never throws.
  final Future<void> Function() read;
  final Duration debounce;
  final Duration minGap;
  final DateTime Function() _now;

  Timer? _timer;
  bool _isDirty = false;
  bool _isStale = false;
  bool _isRunning = false;
  bool _isForeground = true;
  int _gen = 0;
  DateTime? _lastEnd;

  /// Live re-reads started so far (tests, logs).
  int reads = 0;

  bool get isForeground => _isForeground;

  /// The Inbox missed a change while hidden: one read is owed.
  bool get isStale => _isStale;

  void start() {
    final s = WidgetsBinding.instance.lifecycleState;
    _isForeground = s == null || s == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cancel();
  }

  /// A socket event. Only the web's work events count (see [InboxLiveRule]).
  void onEvent(Map<String, dynamic> event) {
    final name = InboxLiveRule.nameOf(event);
    if (InboxLiveRule.isWork(name)) _signal(name);
  }

  /// The connection is back: the web's `status_change connected`, one resync.
  void onReconnect() => _signal('resync');

  void _signal(String name) {
    switch (_stateNow) {
      case InboxLiveState.closed:
        AppLog.i('inbox_live', '$name dropped (inbox not open)');
        return;
      case InboxLiveState.hidden:
        _isStale = true;
        AppLog.i('inbox_live', '$name deferred (inbox hidden)');
        return;
      case InboxLiveState.active:
        _isDirty = true;
        AppLog.i('inbox_live', '$name queued');
        _arm();
    }
  }

  InboxLiveState get _stateNow {
    final s = state();
    if (s == InboxLiveState.active && !_isForeground) {
      return InboxLiveState.hidden;
    }
    return s;
  }

  /// The tab was shown again or the app came back: the one owed read.
  void onShown() {
    if (!_isStale || _stateNow != InboxLiveState.active) return;
    _isStale = false;
    _isDirty = true;
    AppLog.i('inbox_live', 'stale read queued (inbox shown)');
    _arm();
  }

  /// The Inbox did its own first read: nothing is owed.
  void clearStale() => _isStale = false;

  /// Signed out or another person: pending work is dropped, and a read in
  /// flight is not followed by another.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _isDirty = false;
    _isStale = false;
    _gen++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) onShown();
  }

  void _arm() {
    if (_isRunning) return;
    _timer?.cancel();
    var wait = debounce;
    final end = _lastEnd;
    if (end != null) {
      final left = minGap - _now().difference(end);
      if (left > wait) wait = left;
    }
    _timer = Timer(wait, _fire);
  }

  void _fire() {
    _timer = null;
    if (_stateNow != InboxLiveState.active) {
      if (_isDirty && _stateNow == InboxLiveState.hidden) _isStale = true;
      _isDirty = false;
      AppLog.i('inbox_live', 'read deferred (inbox hidden)');
      return;
    }
    if (isBusy()) {
      _arm();
      return;
    }
    _isDirty = false;
    fireAndLog('inbox_live', _run);
  }

  Future<void> _run() async {
    final gen = _gen;
    _isRunning = true;
    reads++;
    final watch = Stopwatch()..start();
    try {
      await read();
    } finally {
      _isRunning = false;
      _lastEnd = _now();
      AppLog.i('inbox_live', 'read done in ${watch.elapsedMilliseconds} ms');
      if (gen == _gen && _isDirty) _arm();
    }
  }
}
