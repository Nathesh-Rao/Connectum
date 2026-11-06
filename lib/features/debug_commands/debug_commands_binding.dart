import 'package:get/get.dart';

import 'debug_commands_controller.dart';

class DebugCommandsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(DebugCommandsController.new);
  }
}
