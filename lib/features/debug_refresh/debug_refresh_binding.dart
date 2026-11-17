import 'package:get/get.dart';

import 'debug_refresh_controller.dart';

class DebugRefreshBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugRefreshController());
  }
}
