import 'package:get/get.dart';

import '../../data/notifications/local_notification_service.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/feed_repository.dart';
import '../../data/socket/connectivity_service.dart';
import 'notification_router.dart';
import 'notifications_controller.dart';

class NotificationsBinding extends Bindings {
  @override
  void dependencies() {
    if (Get.isRegistered<NotificationsController>()) return;
    Get.put(
      NotificationsController(
        feed: Get.find<FeedRepository>(),
        router: Get.find<NotificationRouter>(),
        notifications: Get.find<LocalNotificationService>(),
        connectivity: Get.find<ConnectivityService>(),
        conversations: Get.find<ConversationRepository>(),
      ),
      permanent: true,
    );
  }
}
