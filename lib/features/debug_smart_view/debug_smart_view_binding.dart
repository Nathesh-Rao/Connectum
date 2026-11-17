import 'package:get/get.dart';

import '../../data/repositories/smart_view_repository.dart';
import '../../data/repositories/ticket_repository.dart';
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
