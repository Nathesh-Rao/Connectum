import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import 'enterprise_created_controller.dart';

class EnterpriseCreatedBinding extends Bindings {
  @override
  void dependencies() {
    final args = (Get.arguments as Map?) ?? {};
    final sample = SeedUi.isActive && args.isEmpty;
    Get.lazyPut(
      () => EnterpriseCreatedController(
        name: sample ? SeedUi.sampleEnterpriseName : '${args['name'] ?? ''}',
        enterpriseId: sample ? SeedUi.currentOrgId : '${args['id'] ?? ''}',
      ),
    );
  }
}
