import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import 'models/session_info.dart';

class SessionStore {
  static const _storage = FlutterSecureStorage();
  static const _currentKey = 'session.current';

  final current = Rxn<SessionInfo>();
  String? _token;

  String? get token => _token;
  String? get orgId => current.value?.orgId;
  String? get userId => current.value?.userId;
  bool get hasSession => current.value != null && _token != null;

  Future<void> load() async {
    final raw = await _storage.read(key: _currentKey);
    if (raw == null) return;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final info = SessionInfo(
      orgId: json['orgId'] as String,
      userId: json['userId'] as String,
      expiresTs: json['expiresTs'] as int?,
    );
    final token = await _storage.read(key: 'token.${info.orgId}');
    if (token == null) return;
    _token = token;
    current.value = info;
  }

  Future<void> save(SessionInfo info, String token) async {
    await _storage.write(key: 'token.${info.orgId}', value: token);
    await _storage.write(
      key: _currentKey,
      value: jsonEncode({
        'orgId': info.orgId,
        'userId': info.userId,
        'expiresTs': info.expiresTs,
      }),
    );
    _token = token;
    current.value = info;
  }

  Future<void> clear() async {
    final org = orgId;
    if (org != null) await _storage.delete(key: 'token.$org');
    await _storage.delete(key: _currentKey);
    _token = null;
    current.value = null;
  }

  Future<String> deviceId() async {
    final existing = await _storage.read(key: 'device_id');
    if (existing != null) return existing;
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _storage.write(key: 'device_id', value: id);
    return id;
  }

  Future<String?> readValue(String key) => _storage.read(key: key);

  Future<void> writeValue(String key, String value) =>
      _storage.write(key: key, value: value);
}
