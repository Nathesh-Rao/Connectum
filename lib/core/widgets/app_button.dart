import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

enum _AppButtonKind { primary, secondary, icon }

class AppButton extends StatefulWidget {
  const AppButton.primary({
    super.key,
    required String this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
  }) : _kind = _AppButtonKind.primary,
       semanticLabel = null;

  const AppButton.secondary({
    super.key,
    required String this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
  }) : _kind = _AppButtonKind.secondary,
       semanticLabel = null;

  const AppButton.icon({
    super.key,
    required IconData this.icon,
    required this.onPressed,
    required String this.semanticLabel,
  }) : _kind = _AppButtonKind.icon,
       label = null,
       isLoading = false;

  final _AppButtonKind _kind;
  final String? label;
  final String? semanticLabel;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(
    vsync: this,
    value: 1,
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
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = switch (widget._kind) {
      _AppButtonKind.icon => _buildIcon(),
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
    final foreground = isPrimary ? AppColors.background : AppColors.ink;
    final background = isPrimary
        ? (_isEnabled || widget.isLoading
              ? AppColors.accent
              : AppColors.accentDisabled)
        : AppColors.background;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.controlHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.controlAll,
          border: isPrimary ? null : Border.all(color: AppColors.inputBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Center(
            child: widget.isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.label!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.button.copyWith(color: foreground),
                        ),
                      ),
                      if (widget.icon != null) ...[
                        const SizedBox(width: AppSpacing.sm),
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
