import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_fab.dart';

/// Debug only: the bubble primary button and FAB in each size and state.
class ButtonSamples extends StatelessWidget {
  const ButtonSamples({super.key});

  static const wideWidth = 363.0;
  static const mediumWidth = 220.0;
  static const narrowWidth = 140.0;

  @override
  Widget build(BuildContext context) {
    Widget caption(String text) => Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.xxs,
      ),
      child: Text(
        text,
        style: AppText.caption.copyWith(color: AppColors.muted),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        caption('Default, wide (363)'),
        SizedBox(
          width: wideWidth,
          child: AppButton.primary(
            key: const Key('sample-primary'),
            label: 'Continue',
            icon: Icons.arrow_forward,
            onPressed: () {},
          ),
        ),
        caption('Medium (220)'),
        SizedBox(
          width: mediumWidth,
          child: AppButton.primary(label: 'Continue', onPressed: () {}),
        ),
        caption('Narrow (140)'),
        SizedBox(
          width: narrowWidth,
          child: AppButton.primary(
            label: 'Get started',
            isCentered: true,
            onPressed: () {},
          ),
        ),
        caption('Disabled'),
        const SizedBox(
          width: wideWidth,
          child: AppButton.primary(label: 'Continue', onPressed: null),
        ),
        caption('Loading'),
        SizedBox(
          width: wideWidth,
          child: AppButton.primary(
            label: 'Continue',
            isLoading: true,
            onPressed: () {},
          ),
        ),
        caption('FAB circle and extended'),
        Row(
          children: [
            AppFab(
              key: const Key('sample-fab'),
              semanticLabel: 'Add',
              onPressed: () {},
              child: const Icon(Icons.add, color: AppColors.white),
            ),
            const SizedBox(width: AppSpacing.md),
            AppFab(
              semanticLabel: 'New chat',
              label: 'New chat',
              onPressed: () {},
              child: const Icon(Icons.add, color: AppColors.white),
            ),
          ],
        ),
      ],
    );
  }
}
