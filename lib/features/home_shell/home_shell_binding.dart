import 'package:get/get.dart';

import '../../core/routes/deep_link_service.dart';
import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import 'package:connectum/features/ai_agents/ai_agents.dart';
import 'package:connectum/features/chats/chats.dart';
import 'package:connectum/features/hand_on/hand_on.dart';
import 'package:connectum/features/inbox/inbox.dart';
import 'package:connectum/features/notifications/notifications.dart';
import 'package:connectum/features/security/security.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import 'package:connectum/features/submissions/submissions.dart';
import '../../data/notifications/local_notification_service.dart';
import '../../data/session_store.dart';
import 'home_shell_controller.dart';

class HomeShellBinding extends Bindings {
  @override
  void dependencies() {
    SmartViewBinding().dependencies();
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
        smartView: Get.find<SmartViewController>(),
        tour: Get.isRegistered<TourService>() ? Get.find<TourService>() : null,
      ),
    );
    Get.put(HandOnController(Get.find<HandOnRepository>()));
    ChatsBinding().dependencies();
    AiAgentsBinding().dependencies();
    SubmissionsBinding().dependencies();
    InboxBinding().dependencies();
  }
}
