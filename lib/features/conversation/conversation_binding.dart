import 'package:get/get.dart';

import 'conversation_controller.dart';

class ConversationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => ConversationController(
        conversationId: Uri.decodeComponent(Get.parameters['id'] ?? ''),
      ),
    );
  }
}
