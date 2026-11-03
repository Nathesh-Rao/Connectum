import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';

const _tileIcons = [
  Icons.domain,
  Icons.work_outline,
  Icons.people_outline,
  Icons.school_outlined,
  Icons.local_hospital_outlined,
];

class EnterpriseTile extends StatelessWidget {
  const EnterpriseTile({
    super.key,
    required this.index,
    required this.isCurrent,
  });

  final int index;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final palette =
        AppColors.tilePalettes[index % AppColors.tilePalettes.length];
    return Container(
      width: AppSpacing.tileSize,
      height: AppSpacing.tileSize,
      decoration: BoxDecoration(
        color: isCurrent ? AppColors.accentTint : palette.background,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.tile)),
        border: Border.all(
          color: isCurrent ? AppColors.tileCurrentBorder : palette.border,
        ),
      ),
      child: Icon(
        _tileIcons[index % _tileIcons.length],
        size: 22,
        color: isCurrent ? AppColors.accent : palette.foreground,
      ),
    );
  }
}

class EnterpriseCurrentCheck extends StatelessWidget {
  const EnterpriseCurrentCheck({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 23,
      height: 23,
      decoration: const BoxDecoration(
        color: AppColors.accentTint,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, size: 13, color: AppColors.accent),
    );
  }
}
