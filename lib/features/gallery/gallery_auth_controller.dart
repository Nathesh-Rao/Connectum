import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

class GalleryAuthController extends GetxController {
  final email = TextEditingController();
  final code = TextEditingController();

  @override
  void onClose() {
    email.dispose();
    code.dispose();
    super.onClose();
  }
}
