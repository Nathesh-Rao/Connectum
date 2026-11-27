import 'package:get/get.dart';

import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../home_shell/home_shell_controller.dart';
import 'submissions_controller.dart';

class SubmissionsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => SubmissionsController(
        submissions: Get.find<SubmissionRepository>(),
        connectivity: Get.find<ConnectivityService>(),
        shell: Get.find<HomeShellController>(),
      ),
    );
  }
}
