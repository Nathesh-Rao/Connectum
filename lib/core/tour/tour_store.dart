import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:connectum/core/log/log.dart';
import 'tour_id.dart';

/// Which tours a person has seen, kept per user, tour and tour version. The
/// app has no plain preference store, so it rides on the secure storage the
/// session already uses (never restored onto another device).
class TourStore {
  TourStore({
    Future<String?> Function(String key)? read,
    Future<void> Function(String key, String value)? write,
    Future<void> Function(String key)? delete,
  }) : _read = read ?? _readSecure,
       _write = write ?? _writeSecure,
       _delete = delete ?? _deleteSecure;

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static Future<String?> _readSecure(String key) => _storage.read(key: key);

  static Future<void> _writeSecure(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<void> _deleteSecure(String key) => _storage.delete(key: key);

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;
  final Future<void> Function(String key) _delete;

  final _cache = <String, bool>{};

  static String keyOf(String userId, TourId id) =>
      'tour.$userId.${id.name}.v${id.version}';

  static String introKeyOf(String userId) => 'tour.$userId.intro.v1';

  Future<bool> isIntroSeen(String userId) => _isSet(introKeyOf(userId));

  Future<void> markIntroSeen(String userId) => _set(introKeyOf(userId));

  Future<void> resetIntro(String userId) async {
    final key = introKeyOf(userId);
    _cache[key] = false;
    try {
      await _delete(key);
    } catch (e, st) {
      AppLog.e('tour_store', e, st);
    }
  }

  Future<bool> isSeen(String userId, TourId id) => _isSet(keyOf(userId, id));

  Future<void> markSeen(String userId, TourId id) => _set(keyOf(userId, id));

  Future<bool> _isSet(String key) async {
    final cached = _cache[key];
    if (cached != null) return cached;
    try {
      final isSeen = await _read(key) == '1';
      _cache[key] = isSeen;
      return isSeen;
    } catch (e, st) {
      AppLog.e('tour_store', e, st);
      return false;
    }
  }

  Future<void> _set(String key) async {
    _cache[key] = true;
    try {
      await _write(key, '1');
    } catch (e, st) {
      AppLog.e('tour_store', e, st);
    }
  }

  Future<void> reset(String userId, TourId id) async {
    final key = keyOf(userId, id);
    _cache[key] = false;
    try {
      await _delete(key);
    } catch (e, st) {
      AppLog.e('tour_store', e, st);
    }
  }
}
