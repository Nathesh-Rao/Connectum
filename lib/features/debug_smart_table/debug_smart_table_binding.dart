import 'package:get/get.dart';

import 'debug_smart_table_controller.dart';

class DebugSmartTableBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(DebugSmartTableController.new);
  }
}
