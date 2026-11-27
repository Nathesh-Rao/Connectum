import 'package:get/get.dart';

import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../data/session_store.dart';
import 'security_controller.dart';

class SecurityBinding extends Bindings {
  @override
  void dependencies() {
    if (Get.isRegistered<SecurityController>()) return;
    Get.lazyPut(
      () => SecurityController(
        e2e: Get.find<E2eRepository>(),
        store: Get.find<SessionStore>(),
        connectivity: Get.find<ConnectivityService>(),
      ),
    );
  }
}
