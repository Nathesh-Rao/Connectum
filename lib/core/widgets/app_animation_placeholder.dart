import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text.dart';

class AppAnimationPlaceholder extends StatelessWidget {
  const AppAnimationPlaceholder({
    super.key,
    required this.name,
    this.width = 160,
    this.height = 120,
  });

  final String name;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: AppRadius.mdAll,
      ),
      child: Text(
        '[animation: $name]',
        textAlign: TextAlign.center,
        style: AppText.label.copyWith(color: AppColors.primaryStrong),
      ),
    );
  }
}
