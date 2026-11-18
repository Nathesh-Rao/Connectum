import 'dart:async';

import 'package:flutter/foundation.dart';

import 'crash_reporter.dart';
import 'expected_errors.dart';

/// Holds the active reporter and the rules in front of it. The static
/// [current] lets the few central error sites report without a lookup; main
/// and the tests install one.
class CrashService {
  CrashService(
    this.reporter, {
    DateTime Function()? now,
    this.maxNonFatals = 20,
    this.dedupeWindow = const Duration(seconds: 60),
    this.keyDebounce = const Duration(milliseconds: 500),
  }) : _now = now ?? DateTime.now;

  static CrashService current = CrashService(const NoopCrashReporter());

  final CrashReporter reporter;
  final int maxNonFatals;
  final Duration dedupeWindow;
  final Duration keyDebounce;
  final DateTime Function() _now;

  final _lastSeen = <String, DateTime>{};
  final _pendingKeys = <String, String>{};
  final recentCrumbs = <String>[];
  Timer? _keyTimer;
  int _sent = 0;

  int get sentNonFatals => _sent;

  /// Unexpected errors only, cleaned, once per type+message per window and at
  /// most [maxNonFatals] per run.
  static void nonFatal(Object error, [StackTrace? stack, String? reason]) =>
      current.reportNonFatal(error, stack, reason: reason);

  static void key(String name, String value) =>
      current.setKeyLater(name, value);

  void reportNonFatal(Object error, StackTrace? stack, {String? reason}) {
    try {
      if (!reporter.isEnabled || isExpectedError(error)) return;
      if (_sent >= maxNonFatals) return;
      final clean = sanitizeError(error);
      final id = '${clean.type}|${clean.message}';
      final now = _now();
      final last = _lastSeen[id];
      if (last != null && now.difference(last) < dedupeWindow) return;
      _lastSeen[id] = now;
      _sent++;
      reporter.recordNonFatal(
        clean,
        stack ?? StackTrace.current,
        reason: reason,
      );
    } catch (_) {}
  }

  void addCrumb(String text) {
    recentCrumbs.add(text);
    if (recentCrumbs.length > 5) recentCrumbs.removeAt(0);
    try {
      reporter.log(text);
    } catch (_) {}
  }

  void setKeyLater(String name, String value) {
    _pendingKeys[name] = value;
    _keyTimer ??= Timer(keyDebounce, flushKeys);
  }

  @visibleForTesting
  void flushKeys() {
    _keyTimer = null;
    final keys = Map.of(_pendingKeys);
    _pendingKeys.clear();
    for (final e in keys.entries) {
      try {
        reporter.setKey(e.key, e.value);
      } catch (_) {}
    }
  }
}
