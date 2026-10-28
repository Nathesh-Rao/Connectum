import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_ambient_backdrop.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/app_scaffold.dart';
import 'splash_controller.dart';

class SplashView extends GetView<SplashController> {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      ambient: AppAmbientVariant.splash,
      body: Center(child: AppLogo(width: AppSpacing.splashLogoWidth)),
    );
  }
}
