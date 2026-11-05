import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:webcrypto/webcrypto.dart';

import 'e2e_crypto.dart';
import 'e2e_models.dart';

/// The numbers of the older-device hand-on, from the backend docs
/// (`E2E_NEW_DEVICE_AND_HISTORY.md` 3.2). Budgets are kept below the server's
/// limits because they are per person, not per device.
class HandOnLimits {
  HandOnLimits._();

  /// Boxes per `e2e.sync.put` (the server accepts 1 to 500).
  static const batchSize = 400;
  static const serverMaxItems = 500;

  /// Messages per `e2e.sync.page` answer (the server may return a few more).
  static const pageItems = 400;

  static const window = Duration(minutes: 10);

  /// Calls per [window] this phone allows itself (server: put 400, page 600,
  /// devices 600, approved 60).
  static const budgets = {
    'e2e.sync.put': 300,
    'e2e.sync.page': 450,
    'e2e.devices': 300,
    'e2e.sync.approved': 30,
  };

  /// `rate_limited` waits: 5 s, doubling, capped, and given up after
  /// [rateLimitGiveUp] in total.
  static const rateLimitStart = Duration(seconds: 5);
  static const rateLimitCap = Duration(seconds: 60);
  static const rateLimitGiveUp = Duration(minutes: 10);

  /// Pages read to count what there is to send before the first box.
  static const countPages = 20;

  /// Pages read to find out whether there is anything to give at all.
  static const probePages = 5;

  /// The target's key is looked up again after this many pages.
  static const recheckEveryPages = 25;
}

/// Cuts a list into groups of at most [size] (400): full groups first, the
/// last one partial, never an empty group.
class HandOnBatcher {
  HandOnBatcher._();

  static List<List<T>> split<T>(
    List<T> items, [
    int size = HandOnLimits.batchSize,
  ]) => [
    for (var i = 0; i < items.length; i += size)
      items.sublist(i, i + size > items.length ? items.length : i + size),
  ];
}

/// A rolling window of call times per action. [waitFor] says how long to wait
/// before the next call of [action] stays inside its budget; [record] notes a
/// call. The clock is injectable for the self-test.
class HandOnPacer {
  HandOnPacer({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _calls = <String, List<DateTime>>{};

  Duration waitFor(String action) {
    final budget = HandOnLimits.budgets[action];
    if (budget == null) return Duration.zero;
    final now = _now();
    final list = _calls.putIfAbsent(action, () => []);
    list.removeWhere((t) => now.difference(t) >= HandOnLimits.window);
    if (list.length < budget) return Duration.zero;
    final free = list[list.length - budget].add(HandOnLimits.window);
    return free.difference(now);
  }

  void record(String action) {
    if (!HandOnLimits.budgets.containsKey(action)) return;
    _calls.putIfAbsent(action, () => []).add(_now());
  }

  /// The wait after the [attempt]-th `rate_limited` answer (0 based).
  static Duration backoff(int attempt) {
    final ms = HandOnLimits.rateLimitStart.inMilliseconds * (1 << attempt);
    final cap = HandOnLimits.rateLimitCap.inMilliseconds;
    return Duration(milliseconds: ms > cap ? cap : ms);
  }
}

enum HandOnFailureKind {
  rateLimited,
  anotherFinished,
  deviceGone,
  rejected,
  sessionEnded,
  keyChanged,
  notAllowed,
  unknown,
}

/// A hand-on that stops: the server's error code mapped to words. The texts
/// come from the backend docs where they fit (`E2E_NEW_DEVICE_AND_HISTORY.md`
/// 7.1 and `sessions.md`).
class HandOnFailure implements Exception {
  const HandOnFailure(this.kind, this.message, {this.isRetryable = false});

  final HandOnFailureKind kind;
  final String message;

  /// The person may press Try again.
  final bool isRetryable;

  static const replacedText =
      'You were signed out because this account signed in on another tab or device.';
  static const expiredText = 'Your session has ended. Please sign in again.';

  factory HandOnFailure.fromCode(String code) => switch (code) {
    'rate_limited' => const HandOnFailure(
      HandOnFailureKind.rateLimited,
      'Too many history uploads; try again in a moment.',
      isRetryable: true,
    ),
    'not_waiting' => const HandOnFailure(
      HandOnFailureKind.anotherFinished,
      'That device is not waiting for its earlier messages.',
    ),
    'not_found' => const HandOnFailure(
      HandOnFailureKind.deviceGone,
      'That device was removed from your account.',
    ),
    'invalid' => const HandOnFailure(
      HandOnFailureKind.rejected,
      'The server rejected part of the copy of your messages. Try again.',
      isRetryable: true,
    ),
    'session_replaced' => const HandOnFailure(
      HandOnFailureKind.sessionEnded,
      replacedText,
    ),
    'session_expired' || 'unauthenticated' => const HandOnFailure(
      HandOnFailureKind.sessionEnded,
      expiredText,
    ),
    'forbidden' => const HandOnFailure(
      HandOnFailureKind.notAllowed,
      'This account is not allowed to do that.',
    ),
    _ => const HandOnFailure(
      HandOnFailureKind.unknown,
      'Could not finish.',
      isRetryable: true,
    ),
  };
}

/// The job could not go on for a reason that is not the server's answer: the
/// connection dropped. It is not a failure; the job picks up from the last
/// confirmed page when the connection is back.
class HandOnPaused implements Exception {
  const HandOnPaused();
}

/// The person pressed Stop.
class HandOnCancelled implements Exception {
  const HandOnCancelled();
}

/// Where a hand-on stands, kept after each confirmed page so a killed app or a
/// dropped connection continues from there. [cursor] is the page cursor to ask
/// for next, exactly as the server gave it (null: from the start).
class HandOnCheckpoint {
  const HandOnCheckpoint({
    this.cursor,
    this.sent = 0,
    this.skipped = 0,
    this.already = 0,
  });

  final Object? cursor;
  final int sent;
  final int skipped;
  final int already;

  String toJson() => jsonEncode({
    'cursor': cursor,
    'sent': sent,
    'skipped': skipped,
    'already': already,
  });

  static HandOnCheckpoint? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      int count(Object? v) => v is int && v >= 0 ? v : 0;
      return HandOnCheckpoint(
        cursor: json['cursor'],
        sent: count(json['sent']),
        skipped: count(json['skipped']),
        already: count(json['already']),
      );
    } catch (_) {
      return null;
    }
  }
}

/// What the person sees of a run.
class HandOnProgress {
  const HandOnProgress({
    this.sent = 0,
    this.total = 0,
    this.isTotalKnown = false,
    this.skipped = 0,
    this.already = 0,
    this.isPreparing = false,
    this.note = '',
  });

  final int sent;
  final int total;
  final bool isTotalKnown;
  final int skipped;
  final int already;

  /// Counting what there is to send, before the first box.
  final bool isPreparing;

  /// A short live remark: "Slowing down", empty normally.
  final String note;

  HandOnProgress copyWith({
    int? sent,
    int? total,
    bool? isTotalKnown,
    int? skipped,
    int? already,
    bool? isPreparing,
    String? note,
  }) => HandOnProgress(
    sent: sent ?? this.sent,
    total: total ?? this.total,
    isTotalKnown: isTotalKnown ?? this.isTotalKnown,
    skipped: skipped ?? this.skipped,
    already: already ?? this.already,
    isPreparing: isPreparing ?? this.isPreparing,
    note: note ?? this.note,
  );

  double? get fraction => isTotalKnown && total > 0 ? sent / total : null;
}

/// How a waiting device's name is shown: plain text, control characters
/// removed, cut to 60 characters (`E2E_ENCRYPTION.md` "Alerts when a device is
/// added").
String handOnDeviceName(String label) {
  final clean = label.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '').trim();
  if (clean.isEmpty) return 'A new device';
  return clean.length > 60 ? clean.substring(0, 60) : clean;
}

bool isDeviceId(String id) => RegExp(r'^[0-9a-f]{32}$').hasMatch(id);

/// What one page holds for [targetId], read without any cryptography.
class HandOnScan {
  const HandOnScan({
    this.candidates = 0,
    this.already = 0,
    this.unreadable = 0,
  });

  /// Envelopes with a box for this device and none for the target.
  final int candidates;
  final int already;
  final int unreadable;

  HandOnScan operator +(HandOnScan o) => HandOnScan(
    candidates: candidates + o.candidates,
    already: already + o.already,
    unreadable: unreadable + o.unreadable,
  );

  static HandOnScan of(
    List<String> texts, {
    required String deviceId,
    required String targetId,
  }) {
    final crypto = E2eCrypto();
    var candidates = 0;
    var already = 0;
    var unreadable = 0;
    for (final text in texts) {
      try {
        final e = crypto.parseEnvelope(text);
        if (e.keys.containsKey(targetId)) {
          already++;
        } else if (e.keys.containsKey(deviceId)) {
          candidates++;
        } else {
          unreadable++;
        }
      } catch (_) {
        unreadable++;
      }
    }
    return HandOnScan(
      candidates: candidates,
      already: already,
      unreadable: unreadable,
    );
  }
}

/// The input of one page of cryptography: only bytes, strings and numbers, so
/// it can cross to a worker isolate. [ecdhPkcs8] is this device's private key,
/// held in memory for the run and never logged or stored again.
class HandOnWork {
  const HandOnWork({
    required this.ecdhPkcs8,
    required this.deviceId,
    required this.targetId,
    required this.targetEcdh,
    required this.texts,
  });

  final Uint8List ecdhPkcs8;
  final String deviceId;
  final String targetId;
  final String targetEcdh;
  final List<String> texts;
}

class HandOnPageResult {
  const HandOnPageResult({
    required this.items,
    required this.skipped,
    required this.already,
  });

  final List<Map<String, String>> items;
  final int skipped;
  final int already;
}

/// Makes the boxes for one page: skips what already has a box for the target,
/// counts what this device cannot open. Runs on the main isolate or a worker;
/// touches nothing but its input.
Future<HandOnPageResult> handOnRewrapPage(HandOnWork work) async {
  final crypto = E2eCrypto();
  final key = await EcdhPrivateKey.importPkcs8Key(
    work.ecdhPkcs8,
    EllipticCurve.p256,
  );
  final target = E2eDevicePublic(
    id: work.targetId,
    ecdh: work.targetEcdh,
    sign: '',
  );
  final items = <Map<String, String>>[];
  var skipped = 0;
  var already = 0;
  for (final text in work.texts) {
    try {
      final e = crypto.parseEnvelope(text);
      if (e.keys.containsKey(work.targetId)) {
        already++;
        continue;
      }
      items.add(
        await crypto.rewrap(
          e: e,
          deviceId: work.deviceId,
          ecdhPrivate: key,
          target: target,
        ),
      );
    } catch (_) {
      skipped++;
    }
  }
  return HandOnPageResult(items: items, skipped: skipped, already: already);
}

/// [handOnRewrapPage] on a worker isolate, so a page of cryptography never
/// takes frames from the main isolate. Only [work] crosses over.
Future<HandOnPageResult> handOnRewrapInIsolate(HandOnWork work) =>
    Isolate.run(() => handOnRewrapPage(work));
