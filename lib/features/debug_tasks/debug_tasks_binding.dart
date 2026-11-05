import 'package:get/get.dart';

import '../../data/repositories/approval_repository.dart';
import '../../data/repositories/task_repository.dart';
import 'debug_tasks_controller.dart';

class DebugTasksBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => DebugTasksController(
        tasks: Get.find<TaskRepository>(),
        approvals: Get.find<ApprovalRepository>(),
      ),
    );
  }
}
