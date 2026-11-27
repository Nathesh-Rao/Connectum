import 'package:get/get.dart';

import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/features/home_shell/home_shell.dart';
import 'debug_tasks_controller.dart';

class DebugTasksBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => DebugTasksController(
        tasks: Get.find<TaskRepository>(),
        approvals: Get.find<ApprovalRepository>(),
        shell: Get.isRegistered<HomeShellController>()
            ? Get.find<HomeShellController>()
            : null,
      ),
    );
  }
}
