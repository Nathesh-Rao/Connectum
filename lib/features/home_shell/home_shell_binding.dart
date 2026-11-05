import 'package:get/get.dart';

import '../../core/routes/deep_link_service.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/notifications/local_notification_service.dart';
import '../ai_agents/ai_agents_binding.dart';
import '../notifications/notification_router.dart';
import '../chats/chats_binding.dart';
import '../../data/repositories/e2e_repository.dart';
import '../../data/repositories/hand_on_repository.dart';
import '../hand_on/hand_on_controller.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../profile/profile_binding.dart';
import '../security/security_controller.dart';
import '../submissions/submissions_binding.dart';
import 'home_shell_controller.dart';

class HomeShellBinding extends Bindings {
  @override
  void dependencies() {
    final security = Get.put(
      SecurityController(
        e2e: Get.find<E2eRepository>(),
        store: Get.find<SessionStore>(),
        connectivity: Get.find<ConnectivityService>(),
      ),
    );
    Get.put(
      HomeShellController(
        conversations: Get.find<ConversationRepository>(),
        security: security,
        links: Get.find<DeepLinkService>(),
        notifications: Get.find<LocalNotificationService>(),
        notificationRouter: Get.find<NotificationRouter>(),
      ),
    );
    Get.put(HandOnController(Get.find<HandOnRepository>()));
    ChatsBinding().dependencies();
    AiAgentsBinding().dependencies();
    SubmissionsBinding().dependencies();
    ProfileBinding().dependencies();
  }
}
