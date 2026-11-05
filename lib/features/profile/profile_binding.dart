import 'package:get/get.dart';

import '../../data/repositories/qr_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../chats/enterprise_switcher_controller.dart';
import 'profile_controller.dart';

class ProfileBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => ProfileController(
        store: Get.find<SessionStore>(),
        session: Get.find<SessionRepository>(),
        connectivity: Get.find<ConnectivityService>(),
        switcher: Get.find<EnterpriseSwitcherController>(),
        qr: Get.find<QrRepository>(),
      ),
    );
  }
}
