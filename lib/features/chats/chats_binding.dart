import 'package:get/get.dart';

import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/data/db/db.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../data/api/api_client.dart';
import '../../data/session_store.dart';
import '../home_shell/home_shell_controller.dart';
import 'chats_controller.dart';
import 'chats_tour.dart';
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
        people: Get.find<PeopleRepository>(),
        api: Get.find<ApiClient>(),
        store: store,
        connectivity: connectivity,
      ),
    );
    final shell = Get.find<HomeShellController>();
    final tours = Get.isRegistered<TourService>()
        ? Get.find<TourService>()
        : null;
    Get.put(
      ChatsController(
        conversations: conversations,
        messages: Get.find<MessageRepository>(),
        presence: Get.find<PresenceRepository>(),
        profiles: Get.find<PeopleProfiles>(),
        feed: Get.find<FeedRepository>(),
        store: store,
        connectivity: connectivity,
        db: db,
        shell: shell,
        switcher: switcher,
        newChat: newChat,
        avatars: Get.find<PeopleAvatars>(),
        tour: tours == null
            ? null
            : ChatsTour(service: tours, tabsKey: shell.navKey),
      ),
    );
  }
}
