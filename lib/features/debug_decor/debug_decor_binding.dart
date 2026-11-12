import 'package:get/get.dart';

import 'debug_decor_controller.dart';

class DebugDecorBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugDecorController());
  }
}
