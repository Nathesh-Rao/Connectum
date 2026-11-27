import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../log/app_log.dart';
import 'crash_reporter.dart';

/// Chains the error hooks after whatever is installed now; the old handler
/// always runs first. With reporting off nothing changes from today.
void installCrashHooks(
  CrashReporter reporter, {
  bool shouldListenToIsolate = true,
}) {
  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    if (previousFlutter != null) {
      previousFlutter(details);
    } else {
      FlutterError.presentError(details);
    }
    if (!details.silent) {
      AppLog.unhandled('flutter_error', details.exception, details.stack);
      reporter.recordFatal(
        details.exception,
        details.stack ?? StackTrace.empty,
      );
    }
  };

  final previousPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.unhandled('platform_error', error, stack);
    reporter.recordFatal(error, stack);
    if (reporter.isEnabled) return true;
    return previousPlatform?.call(error, stack) ?? false;
  };

  if (shouldListenToIsolate) {
    Isolate.current.addErrorListener(
      RawReceivePort((dynamic pair) {
        final list = pair as List<dynamic>;
        AppLog.unhandled(
          'isolate_error',
          list.first as Object,
          StackTrace.fromString('${list.last}'),
        );
        reporter.recordFatal(
          list.first as Object,
          StackTrace.fromString('${list.last}'),
        );
      }).sendPort,
    );
  }
}
