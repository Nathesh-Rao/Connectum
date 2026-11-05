import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_spacing.dart';

enum AppLoadingSize {
  medium(AppSpacing.loadingMedium),
  large(AppSpacing.loadingLarge);

  const AppLoadingSize(this.extent);

  final double extent;
}

/// The loading animation for full pages and big panes only: medium for panes,
/// large for full screens. Small or inline spots use [AppSpinner]. Reduced motion shows a still frame.
class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.size = AppLoadingSize.medium});

  const AppLoading.large({super.key}) : size = AppLoadingSize.large;

  static const asset = 'assets/lottie/loading.json';
  static const _stillFrame = AlwaysStoppedAnimation<double>(0.5);

  final AppLoadingSize size;

  @override
  Widget build(BuildContext context) {
    final isStill = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Loading',
      excludeSemantics: true,
      child: SizedBox(
        width: size.extent,
        height: size.extent,
        child: Lottie.asset(
          asset,
          controller: isStill ? _stillFrame : null,
          animate: !isStill,
          repeat: true,
          frameRate: FrameRate.composition,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
