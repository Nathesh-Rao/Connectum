import 'dart:async';

import 'socket_service.dart';

/// The one gate every read command goes through (Smart View, the Inbox, the
/// card-actions queue). The server allows 30 commands per 10 s per connection
/// and the outbox keeps its own room under that, so reads share [budget] of
/// them. One read at a time, [gap] apart; a `rate_limited` or `busy` answer
/// pauses every reader for a growing time and the read is sent again.
class ReadGate {
  ReadGate({DateTime Function()? now, Future<void> Function(Duration)? delay})
    : _now = now ?? DateTime.now,
      _delay = delay ?? Future<void>.delayed;

  /// Reads in any [window]. The server's limit is 30; the outbox and chat
  /// sends are not counted here and keep the other 10.
  static const budget = 20;
  static const window = Duration(seconds: 10);

  /// Between two starts.
  static const gap = Duration(milliseconds: 300);

  /// `rate_limited` / `busy`: pause 1, 2, 3, 4 s, then give up.
  static const maxRetries = 4;
  static const retryable = {'rate_limited', 'busy'};

  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  final _starts = <DateTime>[];
  DateTime? _lastStart;
  DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _tail = Future.value();

  /// Reads sent so far (tests).
  int sent = 0;

  /// How long until a read may start (zero: now). Used by queues that keep
  /// their own timers; they call [markStart] when they send.
  Duration waitFor() {
    final now = _now();
    _starts.removeWhere((t) => now.difference(t) >= window);
    var at = _blockedUntil;
    final last = _lastStart;
    if (last != null && last.add(gap).isAfter(at)) at = last.add(gap);
    if (_starts.length >= budget) {
      final free = _starts.first.add(window);
      if (free.isAfter(at)) at = free;
    }
    final wait = at.difference(now);
    return wait.isNegative ? Duration.zero : wait;
  }

  /// A read is being sent now.
  void markStart() {
    final now = _now();
    _starts.add(now);
    _lastStart = now;
    sent++;
  }

  /// Nobody sends a read for [pause] (the server said it is busy).
  void blockFor(Duration pause) {
    final until = _now().add(pause);
    if (until.isAfter(_blockedUntil)) _blockedUntil = until;
  }

  /// The pause after the [attempt]-th refusal (0-based): 1, 2, 3, 4 s.
  static Duration pauseFor(int attempt) => Duration(seconds: attempt + 1);

  /// Runs [send] when a slot is free, after every read asked before it. A
  /// retryable refusal pauses the gate and sends again up to [retries] times;
  /// any other error goes to the caller.
  Future<T> run<T>(Future<T> Function() send, {int retries = maxRetries}) {
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return prev.then((_) async {
      try {
        for (var attempt = 0; ; attempt++) {
          await _waitSlot();
          markStart();
          try {
            return await send();
          } on SocketCallError catch (e) {
            if (retryable.contains(e.code) && attempt < retries) {
              blockFor(pauseFor(attempt));
              continue;
            }
            rethrow;
          }
        }
      } finally {
        done.complete();
      }
    });
  }

  Future<void> _waitSlot() async {
    while (true) {
      final wait = waitFor();
      if (wait == Duration.zero) return;
      await _delay(wait);
    }
  }
}
