import 'package:get/get.dart';

import '../../core/routes/deep_link_service.dart';
import 'debug_connect_controller.dart';

class DebugConnectBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => DebugConnectController(links: Get.find<DeepLinkService>()),
    );
  }
}
