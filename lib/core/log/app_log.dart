import 'package:flutter/foundation.dart';

import '../crash/crash_service.dart';
import 'log_file_sink.dart';

/// The only place logging internals live. Never pass secrets, tokens, keys,
/// recovery codes or message text.
class AppLog {
  AppLog._();

  static const int _maxLength = 300;

  @visibleForTesting
  static void Function(String line)? sink;

  /// The opt-in log file; null until the app has set it up.
  static LogFileSink? file;

  static void e(
    String tag,
    Object error, [
    StackTrace? stack,
    String? context,
  ]) {
    _print(
      'E',
      tag,
      '${error.runtimeType}${context == null ? '' : ' ($context)'}',
      stack: stack,
    );
    if (kReleaseMode) CrashService.nonFatal(error, stack, context);
  }

  /// True only while the log file is on; the API logger checks it first so
  /// nothing is built while logging is off.
  static bool get isFileOn => file?.isEnabled ?? false;

  /// A whole API line: file only, never the console, never cut to 300.
  static void api(String level, String tag, String message) {
    try {
      file?.logRaw(level, tag, message);
    } catch (e) {
      debugPrint('log file failed: ${e.runtimeType}');
    }
  }

  static void w(String tag, String message) => _print('W', tag, message);

  static void i(String tag, String message) => _print('I', tag, message);

  /// An error nobody caught (framework, platform, isolate): the file and the
  /// console only, because the crash hooks already report it.
  static void unhandled(String tag, Object error, StackTrace? stack) =>
      _print('E', tag, '${error.runtimeType} (unhandled)', stack: stack);

  static void _print(
    String level,
    String tag,
    String message, {
    StackTrace? stack,
  }) {
    final text = message.length > _maxLength
        ? '${message.substring(0, _maxLength)}…'
        : message;
    try {
      file?.log(level, tag, text, stack: stack);
    } catch (e) {
      debugPrint('log file failed: ${e.runtimeType}');
    }
    final line = '[$level][$tag] $text';
    final out = sink;
    if (out != null) {
      out(line);
    } else if (!kReleaseMode) {
      debugPrint(line);
    }
  }
}
