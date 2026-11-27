import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectum/core/log/log.dart';

enum SvViewMode { cards, table }

/// The one remembered Smart View setting: Cards or Table, for the whole app.
/// The app has no plain preference store and no new package is allowed, so it
/// rides on the secure storage the session already uses (same iOS
/// accessibility: never restored onto another device). [load] runs before the
/// first frame, so [mode] is a plain synchronous read afterwards.
class SmartViewPrefs {
  SmartViewPrefs({
    SvViewMode mode = SvViewMode.cards,
    Future<void> Function(String value)? write,
  }) : _mode = mode,
       _write = write ?? _store;

  static const _key = 'pref.smartview.mode';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  SvViewMode _mode;
  final Future<void> Function(String value) _write;

  SvViewMode get mode => _mode;

  static Future<void> _store(String value) =>
      _storage.write(key: _key, value: value);

  /// Reads the saved mode; any failure is the default (cards).
  static Future<SmartViewPrefs> load() async {
    try {
      final raw = await _storage.read(key: _key);
      return SmartViewPrefs(
        mode: raw == SvViewMode.table.name
            ? SvViewMode.table
            : SvViewMode.cards,
      );
    } catch (e, st) {
      AppLog.e('sv_prefs', e, st);
      return SmartViewPrefs();
    }
  }

  Future<void> setMode(SvViewMode value) async {
    _mode = value;
    try {
      await _write(value.name);
    } catch (e, st) {
      AppLog.e('sv_prefs', e, st);
    }
  }
}
