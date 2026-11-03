import 'package:get/get.dart';

import 'debug_assets_controller.dart';

class DebugAssetsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugAssetsController());
  }
}
