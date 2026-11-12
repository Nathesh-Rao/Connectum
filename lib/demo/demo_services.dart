import 'package:get/get.dart';

import '../core/routes/app_routes.dart';
import '../data/models/identity_info.dart';
import '../data/models/session_info.dart';
import '../data/session_store.dart';
import '../data/socket/connectivity_service.dart';
import '../data/socket/socket_service.dart';
import '../data/repositories/session_repository.dart';

/// Keeps the session in memory: nothing is read from or written to secure
/// storage.
class DemoSessionStore extends SessionStore {
  final _values = <String, String>{};
  String? _demoToken;

  @override
  String? get token => _demoToken;

  @override
  bool get hasSession => current.value != null && _demoToken != null;

  @override
  Future<void> load() async {}

  @override
  Future<void> save(SessionInfo info, String token) async {
    _demoToken = token;
    current.value = info;
  }

  @override
  Future<void> clear() async {
    _demoToken = null;
    current.value = null;
  }

  @override
  Future<void> clearIdentity() async => identity.value = null;

  @override
  Future<void> saveIdentity(IdentityInfo info) async => identity.value = info;

  @override
  Future<String?> trustFor(String email) async => null;

  @override
  Future<void> saveTrust(String email, String trust) async {}

  @override
  Future<void> clearTrust(String email) async {}

  @override
  Future<String> deviceId() async => 'demo-device';

  @override
  Future<String?> readValue(String key) async => _values[key];

  @override
  Future<void> writeValue(String key, String value) async =>
      _values[key] = value;

  @override
  Future<void> deleteValue(String key) async => _values.remove(key);
}

/// Always online: no plugin, no banners.
class DemoConnectivityService extends ConnectivityService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {
    state.value = AppConnectivity.online;
  }

  @override
  void attachSocket(Rx<SocketState> socketState) {}
}

/// Never opens a connection: it is online from the start and every call is
/// answered with an empty reply.
class DemoSocketService extends SocketService {
  DemoSocketService(super.session, super.connectivity, super.api);

  @override
  void onInit() {
    super.onInit();
    connection.value = SocketState.online;
  }

  @override
  void start() => connection.value = SocketState.online;

  @override
  Future<void> stop() async {}

  @override
  Future<void> connectNow({bool resetBackoff = false}) async {}

  @override
  Future<bool> sendCommand(String line) async => true;

  @override
  Future<Map<String, dynamic>> sdCall(
    String action,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 12),
  }) async => const {};

  @override
  Future<Map<String, dynamic>> hashCall(
    String line,
    String name, {
    Duration timeout = const Duration(seconds: 12),
  }) async => const {};
}

/// Sign in and out change the in-memory session only.
class DemoSessionRepository extends SessionRepository {
  DemoSessionRepository(
    super.store,
    super.db,
    super.api,
    super.socket,
    super.attachmentCache,
    super.links,
  );

  @override
  Future<void> signIn({
    required String orgId,
    required String userId,
    required String token,
    int? expiresTs,
    String? orgName,
  }) async {
    await store.save(
      SessionInfo(orgId: orgId, userId: userId, expiresTs: expiresTs),
      token,
    );
    loginNotice.value = null;
  }

  @override
  Future<void> leaveCurrent({required bool endOnServer}) => store.clear();

  @override
  Future<void> logOut({required String notice}) => _leave(notice);

  @override
  Future<void> signOut() => _leave(null);

  Future<void> _leave(String? notice) async {
    loginEmail.value = store.identity.value?.email;
    await store.clear();
    await store.clearIdentity();
    loginNotice.value = notice;
    Get.offAllNamed(AppRoutes.authentication);
  }
}
