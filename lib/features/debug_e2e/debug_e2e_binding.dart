import 'package:get/get.dart';

import '../../data/db/app_database.dart';
import '../../data/e2e/e2e_key_store.dart';
import '../../data/repositories/e2e_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/socket_service.dart';
import 'debug_e2e_controller.dart';

class DebugE2eBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => DebugE2eController(
        keyStore: E2eKeyStore(),
        e2e: Get.find<E2eRepository>(),
        session: Get.find<SessionStore>(),
        socket: Get.find<SocketService>(),
        db: Get.find<AppDatabase>(),
      ),
    );
  }
}
