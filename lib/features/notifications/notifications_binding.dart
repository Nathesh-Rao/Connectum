import 'package:get/get.dart';

import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../data/notifications/local_notification_service.dart';
import 'notification_router.dart';
import 'notifications_controller.dart';
import 'notifications_tour.dart';

class NotificationsBinding extends Bindings {
  @override
  void dependencies() {
    if (Get.isRegistered<NotificationsController>()) {
      Get.find<NotificationsController>().onScreenOpened();
      return;
    }
    Get.put(
      NotificationsController(
        feed: Get.find<FeedRepository>(),
        router: Get.find<NotificationRouter>(),
        notifications: Get.find<LocalNotificationService>(),
        connectivity: Get.find<ConnectivityService>(),
        conversations: Get.find<ConversationRepository>(),
        tour: Get.isRegistered<TourService>()
            ? NotificationsTour(service: Get.find<TourService>())
            : null,
      ),
      permanent: true,
    ).onScreenOpened();
  }
}
