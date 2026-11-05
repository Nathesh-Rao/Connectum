import 'package:get/get.dart';

import '../../data/repositories/approval_repository.dart';
import '../../data/socket/connectivity_service.dart';
import 'approvals_controller.dart';

class ApprovalsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => ApprovalsController(
        approvals: Get.find<ApprovalRepository>(),
        connectivity: Get.find<ConnectivityService>(),
      ),
    );
  }
}
