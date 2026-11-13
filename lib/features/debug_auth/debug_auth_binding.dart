import 'package:get/get.dart';

import '../../core/routes/invite_service.dart';
import '../../data/api/api_client.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../authentication/authentication_controller.dart';
import 'debug_auth_controller.dart';
import 'scripted_auth_repository.dart';

class DebugAuthBinding extends Bindings {
  @override
  void dependencies() {
    final repo = ScriptedAuthRepository(
      Get.find<ApiClient>(),
      Get.find<SessionStore>(),
      Get.find<SessionRepository>(),
    );
    Get.lazyPut(() => DebugAuthController(repo));
    Get.lazyPut(
      () => AuthenticationController(
        auth: repo,
        session: Get.find<SessionRepository>(),
        connectivity: Get.find<ConnectivityService>(),
        invite: Get.find<InviteService>(),
      ),
      tag: DebugAuthController.tag,
    );
  }
}
