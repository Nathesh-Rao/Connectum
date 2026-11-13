import 'dart:typed_data';

import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../demo/sample_photos.dart';

class DebugPhotoCropController extends GetxController {
  final sample = SamplePhoto.landscape.obs;
  final result = Rxn<Uint8List>();
  final isOpening = false.obs;

  /// Opens the real crop screen on [sample] with the numbers shown, and keeps
  /// the PNG it hands back.
  Future<void> open() async {
    if (isOpening.value) return;
    isOpening.value = true;
    try {
      final bytes = await SamplePhotos.png(sample.value);
      final out = await Get.toNamed(
        AppRoutes.photoCrop,
        arguments: {'bytes': bytes, 'debug': true},
      );
      if (out is Uint8List) result.value = out;
    } finally {
      isOpening.value = false;
    }
  }
}
