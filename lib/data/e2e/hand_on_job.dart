import 'dart:async';

import '../socket/socket_service.dart';
import 'hand_on.dart';

/// One run of the older-device hand-on for one waiting device: count, then per
/// page `e2e.sync.page` -> boxes -> `e2e.sync.put` (400 at most) -> a saved
/// checkpoint, and `e2e.sync.done` at the end. Everything it needs comes in
/// through the constructor, so the self-test can run it against a stand-in
/// server. Ends by returning (done), or by throwing [HandOnFailure],
/// [HandOnPaused] or [HandOnCancelled].
class HandOnJob {
  HandOnJob({
    required this.targetId,
    required this.deviceId,
    required Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
    call,
    required Future<HandOnPageResult> Function(List<String> texts) rewrap,
    required Future<void> Function(HandOnCheckpoint? checkpoint) save,
    required Future<void> Function() verifyTarget,
    required void Function(HandOnProgress progress) onProgress,
    HandOnScan Function(List<String> texts)? scan,
    this.start,
    HandOnPacer? pacer,
    Future<void> Function(Duration)? sleep,
  }) : _call = call,
       _rewrap = rewrap,
       _save = save,
       _verifyTarget = verifyTarget,
       _onProgress = onProgress,
       _scan = scan,
       _pacer = pacer ?? HandOnPacer(),
       _sleep = sleep ?? Future<void>.delayed;

  final String targetId;
  final String deviceId;

  /// The last confirmed page of an earlier run, or null.
  final HandOnCheckpoint? start;

  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  _call;
  final Future<HandOnPageResult> Function(List<String>) _rewrap;
  final Future<void> Function(HandOnCheckpoint?) _save;
  final Future<void> Function() _verifyTarget;
  final void Function(HandOnProgress) _onProgress;
  final HandOnScan Function(List<String>)? _scan;
  final HandOnPacer _pacer;
  final Future<void> Function(Duration) _sleep;

  final _wake = Completer<void>();
  bool _isCancelled = false;
  HandOnProgress _progress = const HandOnProgress();

  void cancel() {
    _isCancelled = true;
    if (!_wake.isCompleted) _wake.complete();
  }

  void _check() {
    if (_isCancelled) throw const HandOnCancelled();
  }

  void _emit(HandOnProgress next) {
    _progress = next;
    _onProgress(next);
  }

  Future<void> _wait(Duration d) async {
    await Future.any([_sleep(d), _wake.future]);
    _check();
  }

  Future<Map<String, dynamic>> _request(
    String action,
    Map<String, dynamic> args,
  ) async {
    var attempt = 0;
    var waited = Duration.zero;
    while (true) {
      _check();
      for (var d = _pacer.waitFor(action); d > Duration.zero;) {
        await _wait(d);
        d = _pacer.waitFor(action);
      }
      _pacer.record(action);
      try {
        return await _call(action, args);
      } on SocketCallError catch (e) {
        if (e.isConnectionGap) throw const HandOnPaused();
        if (e.code != 'rate_limited') throw HandOnFailure.fromCode(e.code);
        final delay = HandOnPacer.backoff(attempt++);
        waited += delay;
        if (waited > HandOnLimits.rateLimitGiveUp) {
          throw HandOnFailure.fromCode(e.code);
        }
        _emit(_progress.copyWith(note: 'Slowing down'));
        await _wait(delay);
        _emit(_progress.copyWith(note: ''));
      }
    }
  }

  List<String> _texts(Map<String, dynamic> page) => [
    for (final item in (page['items'] as List? ?? []).whereType<Map>())
      if (item['text'] is String) item['text'] as String,
  ];

  Future<Map<String, dynamic>> _page(Object? cursor) =>
      _request('e2e.sync.page', {'cursor': ?cursor});

  /// Reads up to [HandOnLimits.countPages] pages from [cursor] to count the
  /// boxes to make. Returns the count and whether the end was reached.
  Future<({int count, bool isComplete})> _count(Object? cursor) async {
    var count = 0;
    var next = cursor;
    for (var i = 0; i < HandOnLimits.countPages; i++) {
      final page = await _page(next);
      final texts = _texts(page);
      count +=
          (_scan?.call(texts) ??
                  HandOnScan.of(texts, deviceId: deviceId, targetId: targetId))
              .candidates;
      next = page['next'];
      if (next == null) return (count: count, isComplete: true);
    }
    return (count: count, isComplete: false);
  }

  Future<void> run() async {
    var checkpoint = start ?? const HandOnCheckpoint();
    _emit(
      HandOnProgress(
        sent: checkpoint.sent,
        skipped: checkpoint.skipped,
        already: checkpoint.already,
        isPreparing: true,
      ),
    );
    // A saved cursor the server no longer understands: start over. Boxes
    // the target already has are skipped, so nothing is sent twice.
    var cursor = checkpoint.cursor;
    ({int count, bool isComplete}) counted;
    try {
      counted = await _count(cursor);
    } on HandOnFailure catch (f) {
      if (f.kind != HandOnFailureKind.rejected || cursor == null) rethrow;
      cursor = null;
      counted = await _count(null);
    }
    var total = checkpoint.sent + counted.count;
    _emit(
      _progress.copyWith(
        total: total,
        isTotalKnown: counted.isComplete,
        isPreparing: false,
      ),
    );

    var pages = 0;
    var sent = checkpoint.sent;
    var skipped = checkpoint.skipped;
    var already = checkpoint.already;
    while (true) {
      final page = await _page(cursor);
      final result = await _rewrap(_texts(page));
      _check();
      for (final batch in HandOnBatcher.split(result.items)) {
        await _request('e2e.sync.put', {'device': targetId, 'items': batch});
        sent += batch.length;
        _emit(_progress.copyWith(sent: sent));
      }
      skipped += result.skipped;
      already += result.already;
      if (counted.isComplete) total = total - result.skipped;
      final next = page['next'];
      checkpoint = HandOnCheckpoint(
        cursor: next,
        sent: sent,
        skipped: skipped,
        already: already,
      );
      await _save(checkpoint);
      _emit(
        _progress.copyWith(
          sent: sent,
          total: total < sent ? sent : total,
          skipped: skipped,
          already: already,
        ),
      );
      if (next == null) break;
      cursor = next;
      if (++pages % HandOnLimits.recheckEveryPages == 0) {
        await _verifyTarget();
      }
    }
    await _request('e2e.sync.done', {'device': targetId});
    await _save(null);
  }
}
