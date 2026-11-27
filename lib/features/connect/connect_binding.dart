import 'package:get/get.dart';

import '../../core/routes/deep_link_service.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../data/session_store.dart';
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
