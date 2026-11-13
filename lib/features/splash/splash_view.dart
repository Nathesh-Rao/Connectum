import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/logo_intro/logo_intro.dart';
import '../../core/widgets/app_ambient_backdrop.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/logo_loader/logo_loader.dart';
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
