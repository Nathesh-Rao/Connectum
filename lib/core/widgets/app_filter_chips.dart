import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

class AppFilterChip {
  const AppFilterChip({required this.label, this.count = 0});

  final String label;
  final int count;
}

/// Text filters with an accent underline on the selected one, for a set that
/// is not known until the data is (the tab bar version needs a fixed count).
class AppFilterChips extends StatelessWidget {
  const AppFilterChips({
    super.key,
    required this.chips,
    required this.selected,
    required this.onSelected,
  });

  final List<AppFilterChip> chips;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: SizedBox(
        height: AppSpacing.filterTabHeight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xl),
                Semantics(
                  button: true,
                  selected: i == selected,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelected(i),
                    child: AnimatedContainer(
                      duration: AppDurations.fast,
                      curve: AppCurves.out,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: i == selected
                                ? AppColors.accent
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: AnimatedDefaultTextStyle(
                        duration: AppDurations.fast,
                        style: i == selected
                            ? AppText.segmentSelected.copyWith(
                                color: AppColors.accentInk,
                              )
                            : AppText.segment,
                        child: Text(
                          chips[i].count > 0
                              ? '${chips[i].label} ${chips[i].count}'
                              : chips[i].label,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
