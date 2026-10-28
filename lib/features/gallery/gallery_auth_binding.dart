import 'package:get/get.dart';

import 'gallery_auth_controller.dart';

class GalleryAuthBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => GalleryAuthController());
  }
}
