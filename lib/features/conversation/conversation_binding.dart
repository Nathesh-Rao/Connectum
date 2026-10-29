import 'package:get/get.dart';

import '../../core/routes/home_reload.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/presence_repository.dart';
import '../../data/repositories/typing_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/socket_service.dart';
import 'conversation_controller.dart';

/// Puts one controller per conversation id (its tag), so another route's
/// disposal can never delete it.
class ConversationBinding extends Bindings {
  @override
  void dependencies() {
    final id = Uri.decodeComponent(Get.parameters['id'] ?? '');
    final controller = Get.put(
      ConversationController(
        conversationId: id,
        messages: Get.find<MessageRepository>(),
        conversations: Get.find<ConversationRepository>(),
        presence: Get.find<PresenceRepository>(),
        typing: Get.find<TypingRepository>(),
        socket: Get.find<SocketService>(),
        store: Get.find<SessionStore>(),
      ),
      tag: id,
    );
    // A home reload takes this screen down first (see HomeReload).
    HomeReload.overlays[id] = (
      retire: controller.retire,
      close: () => Get.delete<ConversationController>(tag: id, force: true),
    );
  }
}
