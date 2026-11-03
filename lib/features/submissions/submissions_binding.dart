import 'package:get/get.dart';

import '../../data/repositories/submission_repository.dart';
import '../../data/socket/connectivity_service.dart';
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
