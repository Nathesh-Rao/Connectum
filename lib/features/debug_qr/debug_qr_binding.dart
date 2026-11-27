import 'package:get/get.dart';

import 'package:connectum/data/repositories/repositories.dart';
import 'debug_qr_controller.dart';

class DebugQrBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugQrController(real: Get.find<QrRepository>()));
  }
}
