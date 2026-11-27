import 'package:get/get.dart';

import '../../data/notifications/local_notification_service.dart';
import 'package:connectum/data/repositories/repositories.dart';
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
