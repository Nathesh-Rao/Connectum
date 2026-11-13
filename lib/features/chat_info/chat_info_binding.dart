import 'package:get/get.dart';

import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/people_avatars.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import 'chat_info_controller.dart';

/// One controller per conversation id (its tag). The conversation screen
/// passes whether it shows the chat as encrypted.
class ChatInfoBinding extends Bindings {
  @override
  void dependencies() {
    final id = Uri.decodeComponent(Get.parameters['id'] ?? '');
    Get.put(
      ChatInfoController(
        conversationId: id,
        isEncryptedHint: Get.arguments == true,
        conversations: Get.find<ConversationRepository>(),
        tickets: Get.find<TicketRepository>(),
        store: Get.find<SessionStore>(),
        connectivity: Get.find<ConnectivityService>(),
        avatars: Get.find<PeopleAvatars>(),
      ),
      tag: id,
    );
  }
}
