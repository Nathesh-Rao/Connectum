import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'splash_controller.dart';

class SplashView extends GetView<SplashController> {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    if (controller.usesLogoIntro) {
      return AppScaffold(
        padding: EdgeInsets.zero,
        isScrollable: false,
        body: Center(
          child: OverflowBox(
            maxWidth: kSplashLogoSize,
            maxHeight: kSplashLogoSize,
            child: LogoIntro(
              size: kSplashLogoSize,
              speed: kSplashIntroSpeed,
              finishAt: kSplashFinishAt,
              onFinished: controller.onIntroCompleted,
            ),
          ),
        ),
      );
    }
    return AppScaffold(
      ambient: AppAmbientVariant.splash,
      body: Center(
        child: LogoLoader(
          controller: controller.loader,
          size: AppSpacing.splashLogoSize,
        ),
      ),
    );
  }
}
