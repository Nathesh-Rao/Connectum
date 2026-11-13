import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../core/widgets/logo_intro/logo_intro.dart';
import '../../core/widgets/logo_loader/logo_loader.dart';

class DebugLogoIntroController extends GetxController {
  static const speeds = [0.25, 0.5, 1.0];

  final intro = LogoIntroController();
  final loader = LogoLoaderController();
  final time = ValueNotifier<double>(0);
  final speed = 1.0.obs;
  final isNavy = false.obs;
  final hasBlur = true.obs;
  final glowFinal = 0.55.obs;
  final isScrubbing = false.obs;

  @override
  void onClose() {
    intro.dispose();
    time.dispose();
    loader.dispose();
    super.onClose();
  }

  void replay() {
    isScrubbing.value = false;
    intro.replay();
  }

  void scrub(double seconds) {
    time.value = seconds;
    isScrubbing.value = true;
  }

  void toggleLoader() => loader.isIdle ? loader.start() : loader.stop();
}
