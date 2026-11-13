import 'package:get/get.dart';

import 'debug_logo_intro_controller.dart';

class DebugLogoIntroBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugLogoIntroController());
  }
}
