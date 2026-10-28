import 'package:get/get.dart';

import 'ai_agents_controller.dart';

class AiAgentsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => AiAgentsController());
  }
}
