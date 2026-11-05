import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/routes/invite_service.dart';
import '../../core/theme/app_motion.dart';
import '../../data/session_store.dart';
import '../invite_code/invite_code_sheet.dart';
import '../splash/splash_controller.dart';

class OnboardingSlide {
  const OnboardingSlide(this.title, this.copy, this.animation);

  final String title;
  final String copy;
  final String animation;
}

class OnboardingController extends GetxController {
  OnboardingController({
    required this.store,
    required this.isReplay,
    required this.invite,
  });

  static const slides = [
    OnboardingSlide(
      'All your conversations in one place',
      'Stay connected with your teams, projects and ideas.',
      'onboarding-conversations',
    ),
    OnboardingSlide(
      'Work across multiple enterprises',
      'Switch, collaborate and keep everything organised.',
      'onboarding-enterprises',
    ),
    OnboardingSlide(
      'Secure, simple and ready to go',
      'Your data and conversations stay protected.',
      'onboarding-security',
    ),
  ];

  final SessionStore store;
  final bool isReplay;
  final InviteService invite;

  final pageController = PageController();
  final copyController = PageController();
  final page = 0.obs;

  @override
  void onInit() {
    super.onInit();
    invite.attach();
    // The copy follows the illustration, so both slide together.
    pageController.addListener(() {
      if (pageController.hasClients && copyController.hasClients) {
        copyController.position.jumpTo(pageController.position.pixels);
      }
    });
  }

  void openInviteSheet() {
    final context = Get.context;
    if (context != null) InviteCodeSheet.show(context);
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

  Future<void> finish() async {
    await store.writeValue(SplashController.onboardingSeenKey, 'true');
    if (isReplay) {
      Get.back<void>();
    } else {
      Get.offNamed(AppRoutes.authentication);
    }
  }

  @override
  void onClose() {
    invite.detach();
    pageController.dispose();
    copyController.dispose();
    super.onClose();
  }
}
