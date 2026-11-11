import 'package:get/get.dart';

import '../../data/ai/ai_repository.dart';
import 'debug_ai_controller.dart';

class DebugAiBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugAiController(Get.find<AiRepository>()));
  }
}
