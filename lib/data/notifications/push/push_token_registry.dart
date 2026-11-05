import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import '../../session_store.dart';
import 'push_service.dart';

/// Keeps the current push token and what goes with it, in secure storage,
/// for the day the server can take it. Nothing is sent: the server has no
/// `push.register` yet. Cleared when the session ends or changes (sign out,
/// `session_replaced`, organisation switch). The token is never logged.
///
/// TODO(push): once the server ships them (proposed in
/// `reference/notification/PUSH_AND_LOCAL_NOTIFICATIONS_PLAN.md` B1):
///   - `push.register {platform: ios|android, token, deviceId?, appVersion}`
///     after login and on every new token;
///   - `push.unregister {token}` on sign out.
/// Both belong in [_register] and [_unregister] below, nowhere else.
class PushTokenRegistry extends GetxService {
  PushTokenRegistry(this._store, this._push);

  final SessionStore _store;
  final PushService _push;

  static const _tokenKey = 'push.token';
  static const _permissionKey = 'push.permission';

  final token = RxnString();
  final isPermitted = false.obs;
  StreamSubscription<String>? _tokens;
  String? _scope;

  @override
  void onInit() {
    super.onInit();
    _scope = _scopeOf();
    _tokens = _push.tokenStream.listen(_onToken);
    ever(_store.current, (_) => _onSessionChanged());
    _load();
  }

  @override
  void onClose() {
    _tokens?.cancel();
    super.onClose();
  }

  String get platform => Platform.isIOS ? 'ios' : 'android';

  String? _scopeOf() =>
      _store.current.value == null ? null : '${_store.orgId}/${_store.userId}';

  Future<void> _load() async {
    token.value = await _store.readValue(_tokenKey);
    isPermitted.value = await _store.readValue(_permissionKey) == 'granted';
  }

  Future<void> _onToken(String value) async {
    token.value = value;
    await _store.writeValue(_tokenKey, value);
    await _register();
  }

  /// Remembers the answer of the permission prompt.
  Future<void> setPermitted(bool value) async {
    isPermitted.value = value;
    await _store.writeValue(_permissionKey, value ? 'granted' : 'denied');
  }

  Future<void> _onSessionChanged() async {
    final next = _scopeOf();
    if (next == _scope) return;
    _scope = next;
    await clear();
    if (next != null) await _register();
  }

  /// Forgets the token here; the provider's copy goes with it.
  Future<void> clear() async {
    await _unregister();
    token.value = null;
    await _store.deleteValue(_tokenKey);
    await _push.unregister();
  }

  // TODO(push): call `push.register` here when the server has it.
  Future<void> _register() async {}

  // TODO(push): call `push.unregister` here when the server has it.
  Future<void> _unregister() async {}
}
