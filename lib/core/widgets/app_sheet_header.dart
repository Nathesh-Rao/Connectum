import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// A sheet's title row: the title (and an optional line under it) and a plain
/// close X with a 44 px tap target.
class AppSheetHeader extends StatelessWidget {
  const AppSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleSize = 20,
  });

  final String title;
  final String? subtitle;
  final double titleSize;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(
      start: AppSpacing.md,
      end: AppSpacing.xxs,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppText.fontFamily,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontFamily: AppText.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.3,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Semantics(
          button: true,
          label: 'Close',
          excludeSemantics: true,
          child: InkResponse(
            onTap: () => Navigator.of(context).pop(),
            radius: AppSpacing.minTapTarget / 2,
            child: const SizedBox(
              width: AppSpacing.minTapTarget,
              height: AppSpacing.minTapTarget,
              child: Icon(Icons.close, size: 22, color: AppColors.muted),
            ),
          ),
        ),
      ],
    ),
  );
}
