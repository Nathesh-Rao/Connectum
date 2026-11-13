import 'dart:typed_data';

import 'package:get/get.dart';

import 'profile_photo_crop_controller.dart';

class ProfilePhotoCropBinding extends Bindings {
  @override
  void dependencies() {
    final args = (Get.arguments as Map?) ?? const {};
    Get.lazyPut(
      () => ProfilePhotoCropController(
        bytes: args['bytes'] as Uint8List,
        isDebug: args['debug'] == true,
      ),
    );
  }
}
