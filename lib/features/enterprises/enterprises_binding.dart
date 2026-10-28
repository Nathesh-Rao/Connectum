import 'package:get/get.dart';

import 'enterprises_controller.dart';

class EnterprisesBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => EnterprisesController());
  }
}
