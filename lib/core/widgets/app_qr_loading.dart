import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_spacing.dart';

/// The loading animation of the QR sheet. Reduced motion shows a still frame.
class AppQrLoading extends StatelessWidget {
  const AppQrLoading({super.key});

  static const asset = 'assets/lottie/qr_loading.json';
  static const _stillFrame = AlwaysStoppedAnimation<double>(0.5);

  @override
  Widget build(BuildContext context) {
    final isStill = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Loading QR code',
      excludeSemantics: true,
      child: SizedBox(
        width: AppSpacing.qrLoading,
        height: AppSpacing.qrLoading,
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
