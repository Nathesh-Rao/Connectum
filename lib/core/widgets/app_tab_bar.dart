import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// Equal-width tabs in a bordered container with a pill that slides between
/// them. The pill, the label colour and the label weight all follow the
/// selected index. Dragging along the bar changes tabs too.
class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
    required this.labels,
  });

  static const _tabHeight = 40.0;

  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<String> labels;

  Duration _duration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : AppDurations.base;

  @override
  Widget build(BuildContext context) {
    final duration = _duration(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Builder(
        builder: (context) {
          int indexAt(double dx) {
            final width = context.size?.width ?? 0;
            if (width <= 0) return selectedIndex;
            return (dx / (width / labels.length)).floor().clamp(
              0,
              labels.length - 1,
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => onChanged(indexAt(d.localPosition.dx)),
            onHorizontalDragUpdate: (d) =>
                onChanged(indexAt(d.localPosition.dx)),
            child: SizedBox(
              height: _tabHeight,
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: duration,
                    curve: AppCurves.out,
                    alignment: Alignment(
                      labels.length < 2
                          ? 0
                          : -1 + 2 * selectedIndex / (labels.length - 1),
                      0,
                    ),
                    child: FractionallySizedBox(
                      widthFactor: 1 / labels.length,
                      heightFactor: 1,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.accentTint,
                          borderRadius: BorderRadius.all(
                            Radius.circular(AppRadius.segment),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < labels.length; i++)
                        Expanded(
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: duration,
                              curve: AppCurves.out,
                              style:
                                  (i == selectedIndex
                                          ? AppText.segmentSelected
                                          : AppText.segment)
                                      .copyWith(
                                        color: i == selectedIndex
                                            ? AppColors.accent
                                            : AppColors.muted,
                                      ),
                              child: Text(labels[i]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
