import 'package:get/get.dart';

import 'debug_chat_controller.dart';

class DebugChatBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugChatController());
  }
}
