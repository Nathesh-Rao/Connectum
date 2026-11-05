import 'package:get/get.dart';

import '../../core/routes/deep_link_service.dart';
import 'invite_code_controller.dart';

class InviteCodeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => InviteCodeController(links: Get.find<DeepLinkService>()));
  }
}
