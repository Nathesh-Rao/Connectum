import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';

/// A compact tappable pill: a label and, when it opens a menu, a chevron.
class SvPill extends StatelessWidget {
  const SvPill({
    super.key,
    required this.label,
    required this.onTap,
    this.hasChevron = true,
    this.isActive = false,
    this.isOutlined = false,
    this.maxWidth = 160,
  });

  final String label;
  final VoidCallback? onTap;
  final bool hasChevron;
  final bool isActive;

  /// A hairline border in the app's input colour and radius.
  final bool isOutlined;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: isOutlined
                  ? AppSpacing.pillTall + 2
                  : AppSpacing.pillTall,
              constraints: BoxConstraints(maxWidth: maxWidth),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: isActive ? AppColors.violetTint : AppColors.fill,
                borderRadius: isOutlined
                    ? AppRadius.controlAll
                    : AppRadius.pillAll,
                border: isOutlined
                    ? Border.all(color: AppColors.inputBorder)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.readableStrong.copyWith(
                        color: isActive
                            ? AppColors.violetStrong
                            : AppColors.ink,
                      ),
                    ),
                  ),
                  if (hasChevron) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    Icon(
                      Icons.expand_more,
                      size: AppSpacing.pillChevron,
                      color: AppColors.muted,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round icon action with a 48 dp tap target and a smaller visible circle.
class SvIconAction extends StatefulWidget {
  const SvIconAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone = AppTones.slate,
    this.isActive = false,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final AppTone tone;
  final bool isActive;
  final int badge;

  @override
  State<SvIconAction> createState() => _SvIconActionState();
}

class _SvIconActionState extends State<SvIconAction> {
  bool _isPressed = false;

  void _press(bool value) {
    if (_isPressed != value) setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;
    final alpha = _isPressed
        ? AppSv.controlPressed
        : widget.isActive
        ? AppSv.controlActive
        : AppSv.controlRest;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        child: SizedBox(
          width: AppSv.controlButton + AppSv.controlGap,
          height: AppSpacing.badgedIconHit,
          child: Center(
            child: AnimatedScale(
              scale: _isPressed ? AppSv.controlPressScale : 1,
              duration: AppDurations.reduced,
              curve: AppCurves.out,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: AppDurations.reduced,
                    width: AppSv.controlButton,
                    height: AppSv.controlButton,
                    decoration: BoxDecoration(
                      color: tone.solid.withValues(alpha: alpha),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.icon,
                      size: AppSpacing.popupMenuIcon + 2,
                      color: tone.solid,
                    ),
                  ),
                  if (widget.badge > 0)
                    Positioned(
                      right: -AppSpacing.xxs,
                      top: -AppSpacing.xxs,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: AppSpacing.unreadBadge - 4,
                          minHeight: AppSpacing.unreadBadge - 4,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.violet,
                          borderRadius: AppRadius.pillAll,
                        ),
                        child: Text(
                          '${widget.badge}',
                          style: AppText.caption.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    )
                  else if (widget.isActive)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        width: AppSv.controlDot,
                        height: AppSv.controlDot,
                        decoration: BoxDecoration(
                          color: tone.solid,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
