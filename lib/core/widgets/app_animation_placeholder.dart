import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text.dart';

class AppAnimationPlaceholder extends StatelessWidget {
  const AppAnimationPlaceholder({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 120,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.accentTint,
        borderRadius: AppRadius.mdAll,
      ),
      child: Text(
        '[animation: $name]',
        textAlign: TextAlign.center,
        style: AppText.label.copyWith(color: AppColors.accentInk),
      ),
    );
  }
}
