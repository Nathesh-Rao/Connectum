import 'dart:async';

import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../api/api_client.dart';
import '../db/app_database.dart';
import '../models/ids.dart';
import '../models/session_info.dart';
import '../redact.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';

class SessionRepository extends GetxService {
  SessionRepository(this._store, this._db, this._api, this._socket);

  static const replacedNotice =
      'You were signed out because this account signed in on another tab or device.';
  static const endedNotice = 'Your session has ended. Please sign in again.';

  final SessionStore _store;
  final AppDatabase _db;
  final ApiClient _api;
  final SocketService _socket;

  final loginNotice = RxnString();
  final _ready = Completer<void>();

  /// Completes once the stored session has been read.
  Future<void> get ready => _ready.future;
  Timer? _poll;
  bool _isHandling = false;

  SessionStore get store => _store;

  @override
  Future<void> onInit() async {
    super.onInit();
    _api.unauthorized.listen((_) => handleAuthFailed());
    ever(_socket.connection, (state) {
      if (state == SocketState.sessionReplaced) handleSessionReplaced();
      if (state == SocketState.authFailed) handleAuthFailed();
      if (state == SocketState.online) _startPolling();
      if (state != SocketState.online) _poll?.cancel();
    });
    await _store.load();
    final info = _store.current.value;
    if (info != null && info.isExpired) {
      await _store.clear();
    } else if (info != null) {
      _socket.start();
    }
    _ready.complete();
  }

  Future<void> signIn({
    required String orgId,
    required String userId,
    required String token,
    int? expiresTs,
    String? orgName,
  }) async {
    await _store.save(
      SessionInfo(orgId: orgId, userId: userId, expiresTs: expiresTs),
      token,
    );
    await _db.insert(
      'INSERT OR REPLACE INTO organisations(org_id, user_id, name, last_active_ts) VALUES(?,?,?,?)',
      [orgId, userId, orgName, DateTime.now().millisecondsSinceEpoch],
    );
    loginNotice.value = null;
    _isHandling = false;
    _socket.start();
  }

  /// Runs the `enter` flow and returns a redacted description of the answer
  /// (key names and value types only) to help settle conflict C1.
  Future<String> enter(String identityToken, String enterpriseId) async {
    final data = await _api.enter(
      identityToken,
      enterpriseId,
      await _store.deviceId(),
    );
    final user = (data['user'] as Map?) ?? {};
    await signIn(
      orgId: idText(data['enterprise'] ?? enterpriseId),
      userId: idText(user['username']),
      token: idText(data['token']),
      expiresTs: data['expiresTs'] == null ? null : intOf(data['expiresTs']),
      orgName: user['name'] as String?,
    );
    return Redact.shape(Redact.value(data));
  }

  /// session_replaced: this account signed in elsewhere. Cached rows and the
  /// outbox for this organisation and user are wiped.
  Future<void> handleSessionReplaced() async {
    final info = _store.current.value;
    if (_isHandling || info == null) return;
    _isHandling = true;
    await _socket.stop();
    await _db.wipeScope(info.orgId, info.userId);
    await _store.clear();
    _goToLogin(replacedNotice);
  }

  /// Expired token or handshake failure: the token goes, the cached rows and
  /// the outbox stay and flush after the next login to the same org and user.
  Future<void> handleAuthFailed([String notice = endedNotice]) async {
    if (_isHandling || _store.current.value == null) return;
    _isHandling = true;
    await _socket.stop();
    await _store.clear();
    _goToLogin(notice);
  }

  Future<void> signOut() async {
    final info = _store.current.value;
    if (info == null) return;
    _isHandling = true;
    try {
      await _api.logout();
    } catch (_) {}
    await _socket.stop();
    await _db.wipeScope(info.orgId, info.userId);
    await _store.clear();
    _goToLogin(null);
  }

  void _goToLogin(String? notice) {
    loginNotice.value = notice;
    Get.offAllNamed(AppRoutes.authentication);
  }

  // The web client polls every 60 s; expiry is otherwise noticed only when
  // the socket receives a line.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) async {
      try {
        final data = await _api.session();
        final expires = data['sessionExpiresTs'];
        final info = _store.current.value;
        final token = _store.token;
        if (expires != null && info != null && token != null) {
          await _store.save(
            SessionInfo(
              orgId: info.orgId,
              userId: info.userId,
              expiresTs: intOf(expires),
            ),
            token,
          );
        }
      } on ApiException catch (_) {}
    });
  }

  @override
  void onClose() {
    _poll?.cancel();
    super.onClose();
  }
}
