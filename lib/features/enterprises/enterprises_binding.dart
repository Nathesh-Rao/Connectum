import 'package:get/get.dart';

import '../../core/routes/deep_link_service.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import 'package:connectum/features/connect/connect.dart';
import '../../data/session_store.dart';
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
        links: Get.find<DeepLinkService>(),
      ),
    );
  }
}
