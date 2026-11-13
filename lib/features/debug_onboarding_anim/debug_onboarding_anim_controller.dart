import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

import '../../core/widgets/onboarding_art/network_tiers.dart';
import '../../core/widgets/onboarding_art/onboarding_art.dart';
import 'frame_stats.dart';

enum LabBackdrop { white, light, dark }

/// Lab state for the three onboarding animations: they share play, pause,
/// replay, seek and speed.
class DebugOnboardingAnimController extends GetxController {
  /// Multiples of the authored HTML speed: 1x is the HTML, 1.25x is the
  /// default (the speed constants of onboarding_art_speed.dart).
  static const speeds = [0.5, 1.0, 1.25, 1.5, 2.0];
  static const maxTime = 20.0;

  final art = <OnboardingArtKind, OnboardingArtController>{
    for (final k in OnboardingArtKind.values) k: OnboardingArtController(),
  };

  final frames = FrameStats();
  final isPlaying = true.obs;
  /// The chosen multiple of the HTML speed, null = each art's own constant.
  final speedChoice = Rxn<double>();
  final isBlueOnly = false.obs;
  final isCropped = true.obs;
  final isTier2 = true.obs;
  final isSymmetric = kNetworkSymmetricDefault.obs;
  final backdrop = LabBackdrop.white.obs;

  @override
  void onInit() {
    super.onInit();
    SchedulerBinding.instance.addTimingsCallback(frames.record);
  }

  /// The time every animation shows (they run in lockstep).
  OnboardingArtController get clock => art[OnboardingArtKind.network]!;

  void togglePlay() {
    if (isPlaying.value) {
      pause();
    } else {
      resume();
    }
  }

  void pause() {
    isPlaying.value = false;
    for (final c in art.values) {
      c.pause();
    }
  }

  void resume() {
    isPlaying.value = true;
    for (final c in art.values) {
      c.resume();
    }
  }

  /// Restarts every intro from t = 0.
  void replay() {
    isPlaying.value = true;
    for (final c in art.values) {
      c.play();
    }
  }

  void seek(double t) {
    isPlaying.value = false;
    for (final c in art.values) {
      c.seek(t);
    }
  }

  void setSpeed(double v) {
    speedChoice.value = v;
    for (final c in art.values) {
      c.speed = v;
    }
  }

  /// Back to each animation's own constant.
  void useDefaultSpeed() {
    speedChoice.value = null;
    for (final c in art.values) {
      c.useDefaultSpeed();
    }
  }

  /// The speed an animation plays at now (choice, else its constant).
  double effectiveSpeed(OnboardingArtKind kind) => speedChoice.value ?? kind.speed;

  @override
  void onClose() {
    SchedulerBinding.instance.removeTimingsCallback(frames.record);
    frames.dispose();
    for (final c in art.values) {
      c.dispose();
    }
    super.onClose();
  }
}
