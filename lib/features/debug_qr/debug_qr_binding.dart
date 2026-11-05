import 'package:get/get.dart';

import '../../data/repositories/qr_repository.dart';
import 'debug_qr_controller.dart';

class DebugQrBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => DebugQrController(real: Get.find<QrRepository>()));
  }
}
