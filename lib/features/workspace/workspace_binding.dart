import 'package:get/get.dart';

import '../../data/repositories/form_options_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../home_shell/home_shell_controller.dart';
import 'workspace_controller.dart';

class WorkspaceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => WorkspaceController(
        submissions: Get.find<SubmissionRepository>(),
        store: Get.find<SessionStore>(),
        connectivity: Get.find<ConnectivityService>(),
        formOptions: Get.find<FormOptionsRepository>(),
        shell: Get.isRegistered<HomeShellController>()
            ? Get.find<HomeShellController>()
            : null,
      ),
    );
  }
}
