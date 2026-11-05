import 'package:get/get.dart';

import '../../core/routes/deep_link_service.dart';
import '../../core/utils/connect_code.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/connect_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import 'connect_target_controller.dart';

class ConnectTargetBinding extends Bindings {
  ConnectTargetBinding(this.target);

  final ConnectCode target;

  @override
  void dependencies() {
    Get.lazyPut(
      () => ConnectTargetController(
        target: target,
        repository: Get.find<ConnectRepository>(),
        auth: Get.find<AuthRepository>(),
        store: Get.find<SessionStore>(),
        session: Get.find<SessionRepository>(),
        connectivity: Get.find<ConnectivityService>(),
        links: Get.find<DeepLinkService>(),
      ),
    );
  }
}
