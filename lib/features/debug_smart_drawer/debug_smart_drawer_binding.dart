import 'package:get/get.dart';

import 'debug_smart_drawer_controller.dart';

class DebugSmartDrawerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugSmartDrawerController());
  }
}
