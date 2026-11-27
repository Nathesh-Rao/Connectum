import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:connectum/core/theme/theme.dart';
import '../../../data/smart_view/sv_prefs.dart';

/// The Cards / Table switch: a rounded track with a violet thumb that slides
/// under the chosen icon.
class SmartViewModeSwitch extends StatelessWidget {
  const SmartViewModeSwitch({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  static const width = 96.0;
  static const height = 34.0;
  static const _pad = 3.0;
  static const _duration = Duration(milliseconds: 220);

  final SvViewMode mode;
  final ValueChanged<SvViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final isTable = mode == SvViewMode.table;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.fill,
          borderRadius: AppRadius.pillAll,
        ),
        child: Padding(
          padding: const EdgeInsets.all(_pad),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: _duration,
                curve: Curves.easeOutCubic,
                alignment: isTable
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: const FractionallySizedBox(
                  widthFactor: 0.5,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.violet,
                      borderRadius: AppRadius.pillAll,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  _Segment(
                    icon: Icons.view_agenda_outlined,
                    label: 'Cards',
                    isSelected: !isTable,
                    onTap: () => _pick(SvViewMode.cards),
                  ),
                  _Segment(
                    icon: Icons.table_chart_outlined,
                    label: 'Table',
                    isSelected: isTable,
                    onTap: () => _pick(SvViewMode.table),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pick(SvViewMode value) {
    if (value == mode) return;
    HapticFeedback.selectionClick();
    onChanged(value);
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                end: isSelected ? AppColors.white : AppColors.cardMuted,
              ),
              duration: SmartViewModeSwitch._duration,
              builder: (context, color, _) =>
                  Icon(icon, size: 18, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
