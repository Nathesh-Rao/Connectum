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
  static const expiredNotice = 'Your session expired. Please sign in again.';
  static const supersededNotice =
      'This account was opened on another device, so this one was signed out. Sign in again to use it here.';

  final SessionStore _store;
  final AppDatabase _db;
  final ApiClient _api;
  final SocketService _socket;

  final loginNotice = RxnString();

  /// Set by a log out so the sign-in screen opens with the email filled in.
  final loginEmail = RxnString();
  final _ready = Completer<void>();

  /// Completes once the stored session has been read.
  Future<void> get ready => _ready.future;
  bool _isHandling = false;

  SessionStore get store => _store;

  @override
  Future<void> onInit() async {
    super.onInit();
    _api.unauthorized.listen((_) => handleAuthFailed());
    ever(_socket.connection, (state) {
      if (state == SocketState.sessionReplaced) handleSessionReplaced();
      if (state == SocketState.authFailed) handleAuthFailed();
      if (state == SocketState.expired) handleAuthFailed(expiredNotice);
      if (state == SocketState.superseded) handleAuthFailed(supersededNotice);
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

  /// Leaves the current enterprise on a switch: closes its socket, asks the
  /// server to end its session (best effort, never awaited) and drops that
  /// organisation's token. Its cached rows and outbox stay (they are scoped by
  /// organisation and user) and go out when the person enters it again.
  Future<void> leaveCurrent({required bool endOnServer}) async {
    final token = _store.token;
    if (_store.current.value == null) return;
    _isHandling = true;
    await _socket.stop();
    if (endOnServer && token != null) {
      unawaited(
        _api.post('/logout', bearer: token).then((_) {}, onError: (_) {}),
      );
    }
    await _store.clear();
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

  Future<int> unsentCount() => _db.unsentCount();

  /// The person's own log out. Ends both server sessions (best effort, a
  /// failure never blocks), stops the socket, drops the organisation token and
  /// the account session, and wipes every cached row and the outbox. Kept:
  /// the encryption keys and key pins, the remember-this-device tokens and the
  /// device id. The people and screens behind it read from the stores, which
  /// are emptied here, so nothing stale is left for the next sign-in.
  Future<void> logOut({required String notice}) async {
    _isHandling = true;
    final email = _store.identity.value?.email;
    final orgToken = _store.token;
    final identityToken = _store.identity.value?.token;
    await Future.wait([
      for (final token in [orgToken, identityToken])
        if (token != null)
          _api
              .post('/logout', bearer: token)
              .timeout(const Duration(seconds: 3))
              .then((_) {}, onError: (_) {}),
    ]);
    await _socket.stop();
    await _db.wipeAll();
    await _store.clear();
    await _store.clearIdentity();
    loginEmail.value = email;
    _goToLogin(notice);
  }

  void _goToLogin(String? notice) {
    loginNotice.value = notice;
    Get.offAllNamed(AppRoutes.authentication);
  }
}
