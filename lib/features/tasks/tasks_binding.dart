import 'package:get/get.dart';

import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../tickets/tickets_controller.dart';
import 'tasks_controller.dart';

class TasksBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => TicketsController(
        tickets: Get.find<TicketRepository>(),
        connectivity: Get.find<ConnectivityService>(),
      ),
    );
    Get.lazyPut(
      () => TasksController(
        tasks: Get.find<TaskRepository>(),
        people: Get.find<GroupRepository>(),
        connectivity: Get.find<ConnectivityService>(),
        tickets: Get.find<TicketsController>(),
      ),
    );
  }
}
