import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';

/// Two or more equal pills in a bordered container; the selected one is
/// filled with the accent tint. Stateless: the selection lives with the caller.
class QrKindSwitch extends StatelessWidget {
  const QrKindSwitch({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  static const _height = 40.0;

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(i),
                  child: AnimatedContainer(
                    duration: AppDurations.base,
                    curve: AppCurves.out,
                    height: _height,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected
                          ? AppColors.primaryTint
                          : Colors.transparent,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppRadius.segment),
                      ),
                    ),
                    child: Text(
                      labels[i],
                      style: i == selected
                          ? AppText.segmentSelected
                          : AppText.segment,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
