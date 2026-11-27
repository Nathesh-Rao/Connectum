import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_skeleton.dart';

/// A table of grey blocks while a spreadsheet is being read.
class SvSheetSkeleton extends StatelessWidget {
  const SvSheetSkeleton({super.key});

  static const _rows = 8;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Reading the spreadsheet',
    child: ExcludeSemantics(
      child: AppSkeletonScope(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              for (var r = 0; r < _rows; r++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      const AppSkeleton(width: 24, height: 14),
                      for (var c = 0; c < 3; c++) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const Expanded(child: AppSkeleton(height: 14)),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
