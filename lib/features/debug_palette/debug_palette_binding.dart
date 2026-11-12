import 'package:get/get.dart';

import 'debug_palette_controller.dart';

class DebugPaletteBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugPaletteController());
  }
}
