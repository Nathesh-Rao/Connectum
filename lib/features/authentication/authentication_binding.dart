import 'package:get/get.dart';

import '../../core/routes/invite_service.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/socket/connectivity_service.dart';
import 'authentication_controller.dart';

/// Every visit to the login route gets its own controller under its own tag.
/// A redirect to login can arrive while the previous login route is still
/// being disposed; sharing one instance would let that disposal close the
/// text controllers the new screen is using.
class AuthenticationBinding extends Bindings {
  int _visits = 0;
  String? tag;

  @override
  void dependencies() {
    tag = 'authentication-${++_visits}';
    Get.lazyPut(
      () => AuthenticationController(
        auth: Get.find<AuthRepository>(),
        session: Get.find<SessionRepository>(),
        connectivity: Get.find<ConnectivityService>(),
        invite: Get.find<InviteService>(),
      ),
      tag: tag,
    );
  }
}
