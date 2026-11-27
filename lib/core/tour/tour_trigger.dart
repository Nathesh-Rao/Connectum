import 'dart:async';

import '../log/app_log.dart';
import 'tour_service.dart';

/// When a screen's tour is tried: a beat after the screen has settled, and
/// again every few seconds while a sheet, the keyboard or a prompt is in the
/// way, up to [maxTries] times. While another tour is on screen ([busy]) it
/// keeps trying until the screen calls [cancel] or [dispose] (screen left). It holds no screen state: the screen says
/// whether it may try ([canTry]) and how to start ([start]).
class TourTrigger {
  TourTrigger({
    required this.canTry,
    required this.start,
    this.settle = const Duration(milliseconds: 800),
    this.retry = const Duration(seconds: 2),
    this.maxTries = 20,
  });

  static const _tag = 'tour_trigger';

  /// False while the screen is not ready (loading, another tab, searching).
  /// Nothing is retried then: the screen calls [schedule] again when it is.
  final bool Function() canTry;
  final Future<TourStart> Function() start;
  final Duration settle;
  final Duration retry;
  final int maxTries;

  Timer? _timer;
  int _tries = 0;
  bool _isDone = false;
  bool _isRunning = false;
  bool _hasStarted = false;
  bool _isDisposed = false;

  /// True once the tour was seen before, failed, or has to wait for another
  /// tour: nothing more is tried on this screen visit.
  bool get isDone => _isDone;
  bool get hasStarted => _hasStarted;
  int get tries => _tries;

  /// Waits [settle], then tries. Calling it again restarts the wait; it does
  /// nothing once the tour started, is done, or the trigger is disposed.
  void schedule() {
    if (_isDone || _hasStarted || _isDisposed) return;
    _timer?.cancel();
    if (!canTry()) return;
    _timer = Timer(settle, _try);
  }

  /// The tour was interrupted or the screen left: stops waiting and allows a
  /// fresh start the next time [schedule] is called.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _hasStarted = false;
    _tries = 0;
  }

  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _try() async {
    if (_isDone || _hasStarted || _isDisposed || _isRunning) return;
    if (!canTry()) return;
    _isRunning = true;
    try {
      final result = await start();
      if (_isDisposed) return;
      switch (result) {
        case TourStart.busy:
          _timer = Timer(retry, _try);
        case TourStart.blocked || TourStart.tooFewSteps:
          if (++_tries < maxTries) _timer = Timer(retry, _try);
        case TourStart.seen || TourStart.failed || TourStart.notReady:
          _isDone = true;
        case TourStart.started:
          _hasStarted = true;
      }
    } catch (e, st) {
      AppLog.e(_tag, e, st);
      _isDone = true;
    } finally {
      _isRunning = false;
    }
  }
}
