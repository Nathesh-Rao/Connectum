import 'package:get/get.dart';

import '../../data/notifications/local_notification_service.dart';
import '../../data/repositories/feed_repository.dart';
import 'debug_notifications_controller.dart';

class DebugNotificationsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => DebugNotificationsController(
        feed: Get.find<FeedRepository>(),
        notifications: Get.find<LocalNotificationService>(),
      ),
    );
  }
}
