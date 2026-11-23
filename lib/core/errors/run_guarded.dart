import 'dart:async';

import 'package:flutter/foundation.dart';

import '../crash/crash_service.dart';
import 'app_error.dart';

/// Fire-and-forget: runs [job], never rethrows. Unexpected errors go to
/// Crashlytics as non-fatal (expected ones, such as offline, are filtered in
/// `CrashService`). [reason] is a short fixed tag, never data.
void runGuarded(
  Future<void> Function() job, {
  String? reason,
  void Function(AppError)? onError,
}) {
  unawaited(guarded<void>(job, reason: reason, onError: onError));
}

/// Like [runGuarded] but awaitable: the result of [job], or null on failure.
Future<T?> guarded<T>(
  Future<T> Function() job, {
  String? reason,
  void Function(AppError)? onError,
}) async {
  try {
    return await job();
  } on AppError catch (e) {
    _log(reason, e);
    _notify(onError, e);
  } catch (e, s) {
    CrashService.nonFatal(e, s, reason);
    final error = AppError.from(e, stack: s);
    _log(reason, error);
    _notify(onError, error);
  }
  return null;
}

void _log(String? reason, AppError e) =>
    debugPrint('guarded[${reason ?? '-'}]: $e');

void _notify(void Function(AppError)? onError, AppError e) {
  if (onError == null) return;
  try {
    onError(e);
  } catch (err, s) {
    CrashService.nonFatal(err, s, 'runGuarded onError');
  }
}
