import 'package:get/get.dart';

import '../../data/form_logic/form_logic_service.dart';
import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import 'form_controller.dart';
import 'models/form_launch.dart';

/// One controller per opening of a form (its tag), so two forms, or a form
/// and its replacement, never share or delete each other's.
class FormBinding extends Bindings {
  @override
  void dependencies() {
    final launch = Get.arguments as FormLaunch;
    Get.put(
      FormController(
        launch: launch,
        submissions: Get.find<SubmissionRepository>(),
        options: Get.find<FormOptionsRepository>(),
        store: Get.find<SessionStore>(),
        connectivity: Get.find<ConnectivityService>(),
        logic: Get.find<FormLogicService>(),
        files: Get.find<FormFileRepository>(),
      ),
      tag: launch.tag,
    );
  }
}
