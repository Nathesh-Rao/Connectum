import 'package:get/get.dart';

import 'debug_smart_overview_controller.dart';

class DebugSmartOverviewBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(DebugSmartOverviewController.new);
  }
}
