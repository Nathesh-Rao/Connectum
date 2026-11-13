import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../core/widgets/logo_intro/logo_intro.dart';
import '../../core/widgets/logo_loader/logo_loader.dart';

class DebugLogoIntroController extends GetxController
    with GetSingleTickerProviderStateMixin {
  static const speeds = [0.25, 0.5, 1.0];

  final time = ValueNotifier<double>(0);
  final speed = 1.0.obs;
  final isNavy = false.obs;
  final isLabelled = false.obs;
  final isPlaying = false.obs;
  final loader = LogoLoaderController();

  late final AnimationController _anim;

  @override
  void onInit() {
    super.onInit();
    _anim = AnimationController(vsync: this)
      ..addListener(() {
        time.value = _anim.value * kLogoIntroTotalMs;
      })
      ..addStatusListener((s) {
        isPlaying.value = s == AnimationStatus.forward;
      });
  }

  @override
  void onReady() {
    super.onReady();
    replay();
  }

  @override
  void onClose() {
    _anim.dispose();
    time.dispose();
    loader.dispose();
    super.onClose();
  }

  void replay() {
    _anim.duration = Duration(
      milliseconds: (kLogoIntroTotalMs / speed.value).round(),
    );
    _anim.forward(from: 0);
  }

  void setSpeed(double value) {
    speed.value = value;
    if (_anim.isAnimating) {
      _anim.duration = Duration(
        milliseconds: (kLogoIntroTotalMs / value).round(),
      );
      _anim.forward(from: _anim.value);
    }
  }

  void scrub(double ms) {
    _anim.stop();
    isPlaying.value = false;
    time.value = ms;
    _anim.value = ms / kLogoIntroTotalMs;
  }

  void toggleLoader() => loader.isIdle ? loader.start() : loader.stop();
}
