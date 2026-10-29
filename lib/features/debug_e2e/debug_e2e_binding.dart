import 'package:get/get.dart';

import '../../data/e2e/e2e_key_store.dart';
import '../../data/repositories/e2e_repository.dart';
import 'debug_e2e_controller.dart';

class DebugE2eBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => DebugE2eController(
        keyStore: E2eKeyStore(),
        e2e: Get.find<E2eRepository>(),
      ),
    );
  }
}
