import 'dart:convert';
import 'dart:io';

import '../../core/log/app_log.dart';

enum LogTextSize {
  small('Small', 11),
  medium('Medium', 12),
  large('Large', 14);

  const LogTextSize(this.label, this.fontSize);

  final String label;
  final double fontSize;
}

/// The viewer's text size, in a small JSON file next to the log (the app has
/// no plain preference store). Never throws.
class LogViewerPrefs {
  const LogViewerPrefs(this.directory);

  final Directory directory;

  File get _file => File('${directory.path}/log_viewer.json');

  Future<LogTextSize> loadSize() async {
    try {
      if (!await _file.exists()) return LogTextSize.medium;
      final raw = jsonDecode(await _file.readAsString());
      final name = raw is Map ? raw['size'] : null;
      return LogTextSize.values.firstWhere(
        (s) => s.name == name,
        orElse: () => LogTextSize.medium,
      );
    } on Object catch (e, st) {
      AppLog.e('log_viewer', e, st, 'prefs load');
      return LogTextSize.medium;
    }
  }

  Future<void> saveSize(LogTextSize size) async {
    try {
      await _file.writeAsString(jsonEncode({'size': size.name}));
    } on Object catch (e, st) {
      AppLog.e('log_viewer', e, st, 'prefs save');
    }
  }
}
