import 'package:get/get.dart';

import '../../core/routes/invite_service.dart';
import '../../data/session_store.dart';
import 'onboarding_controller.dart';

class OnboardingBinding extends Bindings {
  @override
  void dependencies() {
    final arguments = Get.arguments;
    Get.lazyPut(
      () => OnboardingController(
        store: Get.find<SessionStore>(),
        isReplay: arguments is Map && arguments['replay'] == true,
        invite: Get.find<InviteService>(),
      ),
    );
  }
}
