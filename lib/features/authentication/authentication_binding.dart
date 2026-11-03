import 'package:get/get.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/socket/connectivity_service.dart';
import 'authentication_controller.dart';

class AuthenticationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => AuthenticationController(
        auth: Get.find<AuthRepository>(),
        session: Get.find<SessionRepository>(),
        connectivity: Get.find<ConnectivityService>(),
      ),
    );
  }
}
