import 'package:get/get.dart';

import 'package:connectum/data/db/db.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../data/e2e/e2e_key_store.dart';
import '../../data/session_store.dart';
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
