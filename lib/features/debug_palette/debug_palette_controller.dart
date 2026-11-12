import 'package:get/get.dart';

class DebugPaletteController extends GetxController {
  final selectedPill = 0.obs;

  void selectPill(int index) => selectedPill.value = index;
}
