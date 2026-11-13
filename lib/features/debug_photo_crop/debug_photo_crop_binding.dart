import 'package:get/get.dart';

import 'debug_photo_crop_controller.dart';

class DebugPhotoCropBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(DebugPhotoCropController.new);
}
