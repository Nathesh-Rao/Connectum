import 'package:get/get.dart';

import 'package:connectum/data/repositories/repositories.dart';
import 'debug_smart_view_controller.dart';

class DebugSmartViewBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => DebugSmartViewController(
        repo: Get.find<SmartViewRepository>(),
        tickets: Get.find<TicketRepository>(),
      ),
    );
  }
}
