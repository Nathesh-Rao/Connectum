import 'package:get/get.dart';

import '../authentication/authentication_controller.dart';
import 'scripted_auth_repository.dart';

class DebugAuthController extends GetxController {
  DebugAuthController(this.repo);

  static const tag = 'debug-auth';

  final ScriptedAuthRepository repo;
  final outcome = PasswordOutcome.wrong.obs;

  void pick(PasswordOutcome next) {
    repo.outcome = next;
    outcome.value = next;
  }

  @override
  void onClose() {
    Get.delete<AuthenticationController>(tag: tag, force: true);
    super.onClose();
  }
}
