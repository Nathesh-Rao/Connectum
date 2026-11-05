import 'package:get/get.dart';

import '../../core/routes/deep_link_service.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import 'connect_controller.dart';

class ConnectBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => ConnectController(
        auth: Get.find<AuthRepository>(),
        store: Get.find<SessionStore>(),
        session: Get.find<SessionRepository>(),
        connectivity: Get.find<ConnectivityService>(),
        links: Get.find<DeepLinkService>(),
      ),
    );
  }
}
