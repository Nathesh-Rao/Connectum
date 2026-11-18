import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'crash_config.dart';
import 'crash_reporter.dart';
import 'firebase_crash_reporter.dart';

/// Starts Firebase and picks the reporter. A failure or a timeout never
/// blocks or crashes the app start: it falls back to the no-op reporter.
Future<CrashReporter> createCrashReporter({
  bool? isDemo,
  bool? isCollectionOn,
  Future<void> Function()? initFirebase,
  CrashReporter Function(bool isCollectionOn)? makeReporter,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final isOn = isCollectionOn ?? isCrashCollectionOn;
  if (isDemo ?? false) return const NoopCrashReporter();
  try {
    await (initFirebase ?? Firebase.initializeApp)().timeout(timeout);
    final reporter = (makeReporter ?? _real)(isOn);
    await reporter.init().timeout(timeout);
    return reporter.isEnabled ? reporter : const NoopCrashReporter();
  } catch (_) {
    debugPrint('crash: reporting is off (Firebase did not start)');
    return const NoopCrashReporter();
  }
}

CrashReporter _real(bool isOn) => FirebaseCrashReporter(isCollectionOn: isOn);
