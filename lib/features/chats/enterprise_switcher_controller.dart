import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/home_reload.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_messages.dart';
import '../../data/db/app_database.dart';
import '../../data/models/identity_info.dart';
import '../../data/models/ids.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';

class EnterpriseSwitcherController extends GetxController {
  EnterpriseSwitcherController({
    required this.auth,
    required this.store,
    required this.connectivity,
    required this.db,
  });

  final AuthRepository auth;
  final SessionStore store;
  final ConnectivityService connectivity;
  final AppDatabase db;

  final enteringId = RxnString();
  final message = RxnString();
  final waiting = 0.obs;

  bool get isOffline => connectivity.state.value == AppConnectivity.offline;

  String? get currentOrgId =>
      store.orgId ?? (SeedUi.isActive ? SeedUi.currentOrgId : null);

  List<EnterpriseMembership> get enterprises =>
      store.identity.value?.enterprises ?? const [];

  String get currentName {
    for (final m in enterprises) {
      if (m.enterprise == currentOrgId) return m.name;
    }
    return currentOrgId ?? 'this enterprise';
  }

  /// Called when the sheet opens: clears the last message and counts what is
  /// still waiting to send in the current enterprise.
  Future<void> prepare() async {
    message.value = null;
    enteringId.value = null;
    final org = store.orgId;
    final user = store.userId;
    if (org == null || user == null) {
      waiting.value = 0;
      return;
    }
    final rows = await db.query(
      'SELECT COUNT(*) AS n FROM outbox WHERE org_id = ? AND user_id = ? '
      "AND status IN ('pending','sending') AND kind IN ('message','reply')",
      [org, user],
    );
    waiting.value = intOf(rows.first['n']);
  }

  Future<void> switchTo(EnterpriseMembership m) async {
    if (enteringId.value != null) return;
    message.value = null;
    if (m.enterprise == currentOrgId) {
      Get.back<void>();
      return;
    }
    if (!m.isActive) {
      message.value = ApiMessages.of(
        ApiException(
          m.status == 'pending' ? 'pending_approval' : 'rejected',
          '',
        ),
      );
      return;
    }
    if (isOffline) {
      message.value = 'Switching needs a connection.';
      return;
    }
    enteringId.value = m.enterprise;
    try {
      // Sample data has no server: a pause stands in for `enter` so the
      // switch navigation can be exercised without a real session.
      if (SeedUi.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      } else {
        await auth.enter(m.enterprise);
      }
      await HomeReload.run();
    } on UnsupportedStep catch (e) {
      message.value =
          "This enterprise needs a step the app doesn't support yet: ${e.reasons.join(', ')}.";
    } on ApiException catch (e) {
      message.value = e.code == 'unauthenticated'
          ? 'Your account session ended. Sign in again from the enterprises screen.'
          : ApiMessages.of(e);
    } finally {
      enteringId.value = null;
    }
  }

  void joinAnother() {
    Get.back<void>();
    HomeReload.homeBelow = Get.rawRoute;
    Get.toNamed(AppRoutes.enterprises);
  }
}
