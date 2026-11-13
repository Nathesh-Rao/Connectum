import 'package:get/get.dart';

import 'debug_onboarding_controller.dart';

class DebugOnboardingBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugOnboardingController());
  }
}
