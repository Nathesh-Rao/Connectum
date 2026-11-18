import 'package:get/get.dart';

import '../../core/crash/crash_service.dart';
import '../../data/session_store.dart';
import 'debug_crashtest_controller.dart';

class DebugCrashTestBinding extends Bindings {
  @override
  void dependencies() {
    final store = Get.find<SessionStore>();
    Get.lazyPut(
      () => DebugCrashTestController(
        Get.find<CrashService>(),
        emailOf: () => store.identity.value?.email,
      ),
    );
  }
}
