import 'package:get/get.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../connect/connect_binding.dart';
import '../connect/connect_controller.dart';
import 'enterprises_controller.dart';

class EnterprisesBinding extends Bindings {
  @override
  void dependencies() {
    ConnectBinding().dependencies();
    Get.lazyPut(
      () => EnterprisesController(
        auth: Get.find<AuthRepository>(),
        store: Get.find<SessionStore>(),
        session: Get.find<SessionRepository>(),
        connectivity: Get.find<ConnectivityService>(),
        connect: Get.find<ConnectController>(),
      ),
    );
  }
}
