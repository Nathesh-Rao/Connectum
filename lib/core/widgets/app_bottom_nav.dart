import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_png_icon.dart';

class AppNavItem {
  const AppNavItem({
    required this.label,
    required this.selectedAsset,
    required this.unselectedAsset,
    this.showDot = false,
  });

  final String label;
  final String selectedAsset;
  final String unselectedAsset;
  final bool showDot;
}

/// The bottom bar: fixed, background running into the system inset, a plain
/// row of items of at least 48 dp. The active one is told apart by the
/// accent icon and label only.
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.white,
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
          child: Row(
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

  static const _swap = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive ? AppColors.purple : AppColors.muted;
    final isStill = MediaQuery.disableAnimationsOf(context);
    final duration = isStill ? Duration.zero : _swap;
    final item = widget.item;
    return Semantics(
      button: true,
      selected: widget.isActive,
      label: item.label,
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
                const SizedBox(height: AppSpacing.xxs),
                SizedBox(
                  width: AppSpacing.navIconBox,
                  height: AppSpacing.navIconBox,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: AnimatedOpacity(
                          opacity: widget.isActive ? 1 : 0,
                          duration: duration,
                          curve: AppCurves.out,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.violetTint,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.navIndicatorGlow,
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      TweenAnimationBuilder<double>(
                        key: ValueKey(widget.isActive),
                        tween: Tween<double>(
                          begin: widget.isActive && !isStill ? 0.9 : 1,
                          end: 1,
                        ),
                        duration: AppDurations.fast,
                        curve: AppCurves.out,
                        builder: (context, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: AppPngIcon(
                          asset: widget.isActive
                              ? item.selectedAsset
                              : item.unselectedAsset,
                          size: AppSpacing.navIcon,
                          color: color,
                        ),
                      ),
                      if (item.showDot)
                        Positioned(
                          top: 2,
                          right: 0,
                          child: Container(
                            width: AppSpacing.navDot,
                            height: AppSpacing.navDot,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryBright,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: AppCurves.out,
                  style: AppText.label.copyWith(
                    color: color,
                    height: 1.2,
                    fontWeight: widget.isActive
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                  child: Text(item.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
