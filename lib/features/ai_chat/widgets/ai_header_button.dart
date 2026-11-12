import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// The AI icon of the chat header: a soft accent circle behind a 24 dp
/// Material icon, 48 dp to tap.
class AiHeaderButton extends StatelessWidget {
  const AiHeaderButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  static const _circle = 36.0;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'AI',
      child: Semantics(
        button: true,
        label: 'AI',
        excludeSemantics: true,
        child: InkResponse(
          onTap: onPressed,
          radius: AppSpacing.badgedIconHit / 2,
          child: SizedBox(
            width: AppSpacing.badgedIconHit,
            height: AppSpacing.badgedIconHit,
            child: Center(
              child: Container(
                width: _circle,
                height: _circle,
                decoration: const BoxDecoration(
                  color: AppColors.violetTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 24,
                  color: AppColors.violet,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
