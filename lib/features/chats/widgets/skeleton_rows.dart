import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_skeleton.dart';

class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonScope(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        itemCount: 8,
        itemBuilder: (context, i) => SizedBox(
          height: AppSpacing.chatRowHeight,
          child: Row(
            children: [
              const AppSkeleton(
                width: AppSpacing.avatar,
                height: AppSpacing.avatar,
                isCircle: true,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: 0.4 + (i % 3) * 0.12,
                      child: const AppSkeleton(height: AppSpacing.sm),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const AppSkeleton(height: AppSpacing.xs),
                    const SizedBox(height: AppSpacing.xs),
                    const FractionallySizedBox(
                      widthFactor: 0.3,
                      child: AppSkeleton(height: AppSpacing.xs),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
