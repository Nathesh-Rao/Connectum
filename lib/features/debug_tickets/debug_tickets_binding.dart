import 'package:get/get.dart';

import 'package:connectum/data/repositories/repositories.dart';
import 'debug_tickets_controller.dart';

class DebugTicketsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => DebugTicketsController(tickets: Get.find<TicketRepository>()),
    );
  }
}
