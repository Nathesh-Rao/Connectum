import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class GalleryController extends GetxController {
  final singleLine = TextEditingController();
  final multiline = TextEditingController();
  final withError = TextEditingController(text: 'not-an-email');

  Future<void> sampleRefresh() =>
      Future<void>.delayed(const Duration(seconds: 2));

  @override
  void onClose() {
    singleLine.dispose();
    multiline.dispose();
    withError.dispose();
    super.onClose();
  }
}
