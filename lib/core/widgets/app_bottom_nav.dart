import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

class AppNavItem {
  const AppNavItem({
    required this.label,
    required this.icon,
    this.showDot = false,
  });

  final String label;
  final IconData icon;
  final bool showDot;
}

/// The bottom bar: fixed, background running into the system inset, each item
/// at least 48 dp, an accent indicator that slides between the items.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.items,
    required this.index,
    required this.onSelected,
  });

  static double heightFor(BuildContext context) =>
      1 +
      AppSpacing.navPaddingTop +
      AppSpacing.navItemHeight +
      AppSpacing.navPaddingBottom +
      MediaQuery.paddingOf(context).bottom;

  final List<AppNavItem> items;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final slot = 2 / items.length;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xxs,
          AppSpacing.navPaddingTop,
          AppSpacing.xxs,
          AppSpacing.navPaddingBottom + MediaQuery.paddingOf(context).bottom,
        ),
        child: SizedBox(
          height: AppSpacing.navItemHeight,
          child: Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _NavButton(
                        item: items[i],
                        isActive: i == index,
                        onTap: () => onSelected(i),
                      ),
                    ),
                ],
              ),
              AnimatedAlign(
                duration: AppDurations.base,
                curve: AppCurves.out,
                alignment: Alignment(-1 + slot * (index + 0.5), 1),
                child: Container(
                  width: AppSpacing.navIndicatorWidth,
                  height: AppSpacing.navIndicatorHeight,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final AppNavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _isPressed = false;

  void _set(bool value) {
    if (!mounted || _isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive ? AppColors.accent : AppColors.muted;
    return Semantics(
      button: true,
      selected: widget.isActive,
      label: widget.item.label,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isPressed ? AppDistances.pressScale : 1,
            duration: AppDurations.fast,
            curve: AppCurves.out,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xs - 2),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      widget.item.icon,
                      size: AppSpacing.navIcon,
                      color: color,
                    ),
                    if (widget.item.showDot)
                      Positioned(
                        top: -1,
                        right: -AppSpacing.xs,
                        child: Container(
                          width: AppSpacing.navDot,
                          height: AppSpacing.navDot,
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs + 2),
                Text(
                  widget.item.label,
                  style: AppText.label.copyWith(
                    color: color,
                    height: 1.2,
                    fontWeight: widget.isActive
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
