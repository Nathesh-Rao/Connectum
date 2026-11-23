import 'package:flutter/foundation.dart';

import '../crash/crash_service.dart';

/// The only place logging internals live. Never pass secrets, tokens, keys,
/// recovery codes or message text.
class AppLog {
  AppLog._();

  static const int _maxLength = 300;

  @visibleForTesting
  static void Function(String line)? sink;

  static void e(String tag, Object error, [StackTrace? stack, String? context]) {
    _print('E', tag, '${error.runtimeType}${context == null ? '' : ' ($context)'}');
    if (kReleaseMode) CrashService.nonFatal(error, stack, context);
  }

  static void w(String tag, String message) => _print('W', tag, message);

  static void i(String tag, String message) => _print('I', tag, message);

  static void _print(String level, String tag, String message) {
    final text = message.length > _maxLength
        ? '${message.substring(0, _maxLength)}…'
        : message;
    final line = '[$level][$tag] $text';
    final out = sink;
    if (out != null) {
      out(line);
    } else if (!kReleaseMode) {
      debugPrint(line);
    }
  }
}
