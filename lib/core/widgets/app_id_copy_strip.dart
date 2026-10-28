import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// "Connectum ID  XXXX-XXXX" with a copy action at the right. While
/// [isCopied] is true the copy icon turns into a green check and a "Copied"
/// label, then switches back. The whole strip is the tap target.
class AppIdCopyStrip extends StatelessWidget {
  const AppIdCopyStrip({
    super.key,
    required this.id,
    required this.isCopied,
    required this.onTap,
  });

  static const _height = 45.0;

  final String id;
  final bool isCopied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isCopied ? 'Copied' : 'Copy Connectum ID',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: _height,
          decoration: const BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: AppColors.line),
            ),
          ),
          child: Row(
            children: [
              const Text('Connectum ID', style: AppText.rowCaption),
              const SizedBox(width: AppSpacing.sm),
              Text(id, style: AppText.idValue),
              const Spacer(),
              AnimatedSwitcher(
                duration: AppDurations.base,
                switchInCurve: AppCurves.out,
                switchOutCurve: AppCurves.out,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerRight,
                  children: [...previous, ?current],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: isCopied
                    ? const Row(
                        key: ValueKey('copied'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Copied', style: AppText.copiedLabel),
                          SizedBox(width: AppSpacing.xs),
                          Icon(Icons.check, size: 16, color: AppColors.yesDot),
                        ],
                      )
                    : const Icon(
                        Icons.copy_rounded,
                        key: ValueKey('copy'),
                        size: 16,
                        color: AppColors.muted,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
