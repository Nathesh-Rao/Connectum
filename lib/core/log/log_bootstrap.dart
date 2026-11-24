import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/app_settings.dart';
import 'app_log.dart';
import 'log_file_sink.dart';
import 'log_formatter.dart';

/// Who is signed in, kept current by the session code, read by the log header.
class LogContextHolder {
  LogContextHolder._();

  static LogContext current = LogContext.unknown;

  static void set(LogContext next) {
    if (next == current) return;
    current = next;
    AppLog.file?.updateContext();
  }
}

/// Flushes the file when the app goes to the background and logs lifecycle.
class LogLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      return;
    }
    AppLog.i('lifecycle', state.name);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      AppLog.file?.flush();
    }
  }
}

class LogBootstrap {
  LogBootstrap._();

  static const _channel = MethodChannel('connectum/device');

  /// Creates the sink, reads the saved switch and starts the lifecycle
  /// observer. Never throws.
  static Future<LogFileSink?> install() async {
    try {
      final sink = LogFileSink(
        directory: () async =>
            Directory('${(await getApplicationSupportDirectory()).path}/logs'),
        context: () => LogContextHolder.current,
        environment: environment,
      );
      AppLog.file = sink;
      await sink.init();
      WidgetsBinding.instance.addObserver(LogLifecycleObserver());
      AppLog.i('app', 'start');
      return sink;
    } catch (e) {
      debugPrint('log install failed: ${e.runtimeType}');
      return null;
    }
  }

  static Future<LogEnvironment> environment() async {
    final version = await AppSettings.version() ?? 'unknown';
    var model = 'unknown';
    var os = Platform.operatingSystem;
    try {
      model = await _channel.invokeMethod<String>('model') ?? model;
      os = Platform.isAndroid
          ? await _channel.invokeMethod<String>('osVersion') ?? os
          : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (e) {
      debugPrint('log environment failed: ${e.runtimeType}');
    }
    return LogEnvironment(version: version, device: '$model, $os');
  }
}
