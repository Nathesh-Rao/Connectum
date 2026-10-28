import 'package:get/get.dart';

import '../../data/api/api_client.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/feed_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/presence_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import '../home_shell/home_shell_controller.dart';
import 'chats_controller.dart';
import 'enterprise_switcher_controller.dart';
import 'new_chat_controller.dart';

class ChatsBinding extends Bindings {
  @override
  void dependencies() {
    final conversations = Get.find<ConversationRepository>();
    final store = Get.find<SessionStore>();
    final connectivity = Get.find<ConnectivityService>();
    final db = Get.find<AppDatabase>();
    final switcher = Get.put(
      EnterpriseSwitcherController(
        auth: Get.find<AuthRepository>(),
        store: store,
        connectivity: connectivity,
        db: db,
      ),
    );
    final newChat = Get.put(
      NewChatController(
        conversations: conversations,
        socket: Get.find<SocketService>(),
        api: Get.find<ApiClient>(),
        store: store,
        connectivity: connectivity,
      ),
    );
    Get.put(
      ChatsController(
        conversations: conversations,
        messages: Get.find<MessageRepository>(),
        presence: Get.find<PresenceRepository>(),
        feed: Get.find<FeedRepository>(),
        store: store,
        connectivity: connectivity,
        db: db,
        shell: Get.find<HomeShellController>(),
        switcher: switcher,
        newChat: newChat,
      ),
    );
  }
}
