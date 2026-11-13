import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/theme/app_motion.dart';

class DebugOnboardingSlide {
  const DebugOnboardingSlide(this.title, this.copy);

  final String title;
  final String copy;
}

/// Debug copy of the onboarding controller: same pages and navigation, but
/// finishing or skipping only goes back; nothing is stored and login is never
/// opened.
class DebugOnboardingController extends GetxController {
  static const slides = [
    DebugOnboardingSlide(
      'All your conversations in one place',
      'Stay connected with your teams, projects and ideas.',
    ),
    DebugOnboardingSlide(
      'Work across multiple enterprises',
      'Switch, collaborate and keep everything organised.',
    ),
    DebugOnboardingSlide(
      'Secure, simple and ready to go',
      'Your data and conversations stay protected.',
    ),
  ];

  final pageController = PageController();
  final copyController = PageController();
  final page = 0.obs;
  final didFinish = false.obs;

  @override
  void onInit() {
    super.onInit();
    // The copy follows the illustration, so both slide together.
    pageController.addListener(() {
      if (pageController.hasClients && copyController.hasClients) {
        copyController.position.jumpTo(pageController.position.pixels);
      }
    });
  }

  bool get isLast => page.value == slides.length - 1;

  void onPageChanged(int index) => page.value = index;

  void goTo(int index) => pageController.animateToPage(
    index,
    duration: AppDurations.page,
    curve: AppCurves.out,
  );

  void next() => isLast ? finish() : goTo(page.value + 1);

  void back() {
    if (page.value > 0) goTo(page.value - 1);
  }

  void finish() {
    didFinish.value = true;
    Get.back<void>();
  }

  @override
  void onClose() {
    pageController.dispose();
    copyController.dispose();
    super.onClose();
  }
}
