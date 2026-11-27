import 'package:get/get.dart';

import '../../core/routes/deep_link_service.dart';
import 'package:connectum/data/repositories/repositories.dart';
import '../../data/session_store.dart';
import 'splash_controller.dart';

class SplashBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(
      SplashController(
        session: Get.find<SessionRepository>(),
        store: Get.find<SessionStore>(),
        deepLinks: Get.find<DeepLinkService>(),
      ),
    );
  }
}
