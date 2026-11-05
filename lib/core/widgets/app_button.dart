import 'package:flutter/gestures.dart';
import './app_spinner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

enum _AppButtonKind { primary, secondary, text, icon }

enum AppTextButtonTone { muted, accent, ink }

class AppButton extends StatefulWidget {
  const AppButton.primary({
    super.key,
    required String this.label,
    required this.onPressed,
    this.icon,
    this.leadingIcon,
    this.isLoading = false,
    this.isCentered = false,
    this.isCompact = false,
  }) : _kind = _AppButtonKind.primary,
       isDanger = false,
       tone = AppTextButtonTone.muted,
       semanticLabel = null;

  const AppButton.secondary({
    super.key,
    required String this.label,
    required this.onPressed,
    this.icon,
    this.leadingIcon,
    this.isDanger = false,
    this.isLoading = false,
  }) : _kind = _AppButtonKind.secondary,
       tone = AppTextButtonTone.muted,
       isCentered = true,
       isCompact = false,
       semanticLabel = null;

  const AppButton.text({
    super.key,
    required String this.label,
    required this.onPressed,
    this.tone = AppTextButtonTone.muted,
    this.leadingIcon,
    this.isLoading = false,
  }) : _kind = _AppButtonKind.text,
       isDanger = false,
       icon = null,
       isCentered = true,
       isCompact = false,
       semanticLabel = null;

  const AppButton.icon({
    super.key,
    required IconData this.icon,
    required this.onPressed,
    required String this.semanticLabel,
  }) : _kind = _AppButtonKind.icon,
       isDanger = false,
       tone = AppTextButtonTone.muted,
       label = null,
       leadingIcon = null,
       isCentered = true,
       isCompact = false,
       isLoading = false;

  final _AppButtonKind _kind;
  final String? label;
  final String? semanticLabel;
  final IconData? icon;
  final IconData? leadingIcon;
  final AppTextButtonTone tone;

  /// Secondary only: the label, icon and border use the error colour.
  final bool isDanger;

  /// Primary buttons put the label on the left and the icon on the right
  /// (the prototype); sheets centre them.
  final bool isCentered;
  final bool isCompact;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> with TickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: AppDurations.spin,
  );

  Offset? _pressOrigin;

  bool get _isEnabled => widget.onPressed != null && !widget.isLoading;

  void _press(PointerDownEvent event) {
    if (!_isEnabled) return;
    _pressOrigin = event.position;
    _springTo(AppDistances.pressScale);
  }

  void _move(PointerMoveEvent event) {
    final origin = _pressOrigin;
    if (origin != null && (event.position - origin).distance > kTouchSlop) {
      _release();
    }
  }

  void _release([PointerEvent? _]) {
    if (_pressOrigin == null) return;
    _pressOrigin = null;
    _springTo(1);
  }

  void _springTo(double target) {
    if (!mounted) return;
    _scale.animateWith(
      SpringSimulation(
        AppCurves.pressSpring,
        _scale.value,
        target,
        _scale.velocity,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.isLoading && widget._kind == _AppButtonKind.text) _spin.repeat();
  }

  @override
  void didUpdateWidget(AppButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._kind != _AppButtonKind.text) return;
    if (widget.isLoading && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.isLoading && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (widget._kind) {
      _AppButtonKind.icon => _buildIcon(),
      _AppButtonKind.text => _buildText(),
      _ => _buildLabelled(),
    };
    return Semantics(
      button: true,
      enabled: _isEnabled,
      label: widget.semanticLabel,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _press,
        onPointerMove: _move,
        onPointerUp: _release,
        onPointerCancel: _release,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _isEnabled ? widget.onPressed : null,
          child: AnimatedBuilder(
            animation: _scale,
            builder: (_, child) =>
                Transform.scale(scale: _scale.value, child: child),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildText() {
    final color = switch (widget.tone) {
      AppTextButtonTone.accent => AppColors.accentInk,
      AppTextButtonTone.ink => AppColors.ink,
      AppTextButtonTone.muted => AppColors.muted,
    };
    final isDimmed = !_isEnabled && !widget.isLoading;
    final tint = isDimmed ? AppColors.taupe : color;
    final label = Text(
      widget.label!,
      style: AppText.action.copyWith(color: tint),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppSpacing.minTapTarget,
        minWidth: AppSpacing.minTapTarget,
      ),
      child: Center(
        widthFactor: 1,
        child: widget.leadingIcon == null
            ? label
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RotationTransition(
                      turns: _spin,
                      child: Icon(widget.leadingIcon, size: 18, color: tint),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    label,
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildIcon() {
    return SizedBox(
      width: AppSpacing.iconButton,
      height: AppSpacing.iconButton,
      child: Icon(
        widget.icon,
        size: 22,
        color: _isEnabled ? AppColors.ink : AppColors.muted,
      ),
    );
  }

  Widget _buildLabelled() {
    final isPrimary = widget._kind == _AppButtonKind.primary;
    final foreground = isPrimary
        ? AppColors.background
        : widget.isDanger
        ? AppColors.error
        : AppColors.ink;
    final background = isPrimary
        ? (_isEnabled || widget.isLoading
              ? AppColors.accent
              : AppColors.accentDisabled)
        : AppColors.background;
    final hasIcons = widget.icon != null || widget.leadingIcon != null;
    final isSpaced = !widget.isCentered && hasIcons;
    final label = Text(
      widget.label!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (widget.isCompact ? AppText.buttonSmall : AppText.button).copyWith(
        color: foreground,
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: widget.isCompact
            ? AppSpacing.compactButtonHeight
            : AppSpacing.controlHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.controlAll,
          border: isPrimary
              ? null
              : Border.all(
                  color: widget.isDanger
                      ? AppColors.error
                      : AppColors.inputBorder,
                ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.isCompact
                ? AppSpacing.compactButtonPaddingX
                : AppSpacing.buttonPaddingX,
          ),
          child: Center(
            child: widget.isLoading
                ? AppSpinner(
                    size: AppSpinnerSize.medium,
                    color: isPrimary ? AppColors.background : AppColors.accent,
                  )
                : Row(
                    mainAxisSize: isSpaced
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    children: [
                      if (widget.leadingIcon != null) ...[
                        Icon(widget.leadingIcon, size: 18, color: foreground),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      isSpaced
                          ? Expanded(child: label)
                          : Flexible(child: label),
                      if (widget.icon != null) ...[
                        if (!isSpaced) const SizedBox(width: AppSpacing.sm),
                        Icon(widget.icon, size: 18, color: foreground),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
