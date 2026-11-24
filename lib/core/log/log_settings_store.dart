import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class LogSettings {
  const LogSettings({
    this.isEnabled = false,
    this.fileName,
    this.created,
    this.version,
  });

  final bool isEnabled;
  final String? fileName;

  /// "2026-11-23 17:34:12 +05:30", for the header of an appended session.
  final String? created;

  /// The app version of the last session that wrote, to spot an update.
  final String? version;
}

/// The switch and the current file name, in a small JSON file next to the
/// logs (the app has no plain preference store). Never throws.
class LogSettingsStore {
  LogSettingsStore(this.directory);

  final Directory directory;

  File get _file => File('${directory.path}/log_settings.json');

  Future<LogSettings> load() async {
    try {
      if (!await _file.exists()) return const LogSettings();
      final raw = jsonDecode(await _file.readAsString());
      if (raw is! Map) return const LogSettings();
      final name = raw['file'];
      final created = raw['created'];
      return LogSettings(
        isEnabled: raw['enabled'] == true,
        fileName: name is String && name.isNotEmpty ? name : null,
        created: created is String ? created : null,
        version: raw['version'] is String ? raw['version'] as String : null,
      );
    } catch (e) {
      debugPrint('log settings load failed: ${e.runtimeType}');
      return const LogSettings();
    }
  }

  Future<void> save(LogSettings s) async {
    try {
      await directory.create(recursive: true);
      await _file.writeAsString(
        jsonEncode({
          'enabled': s.isEnabled,
          'file': s.fileName,
          'created': s.created,
          'version': s.version,
        }),
        flush: true,
      );
    } catch (e) {
      debugPrint('log settings save failed: ${e.runtimeType}');
    }
  }
}
