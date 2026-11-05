import 'package:get/get.dart';

import '../../data/repositories/group_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/socket/connectivity_service.dart';
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
