import 'package:get/get.dart';

import 'debug_onboarding_anim_controller.dart';

class DebugOnboardingAnimBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugOnboardingAnimController());
  }
}
