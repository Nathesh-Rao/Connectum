import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_bubble_surface.dart';

/// The floating action button: the bubble surface of the primary buttons, as a
/// circle holding [child] or, with [label], a pill with [child] and the label.
class AppFab extends StatefulWidget {
  const AppFab({
    super.key,
    required this.semanticLabel,
    required this.onPressed,
    required this.child,
    this.label,
  });

  final String semanticLabel;
  final VoidCallback? onPressed;

  /// The icon, in white.
  final Widget child;

  /// Set for the extended (pill) shape.
  final String? label;

  @override
  State<AppFab> createState() => _AppFabState();
}

class _AppFabState extends State<AppFab> {
  bool _isPressed = false;

  void _set(bool value) {
    if (!mounted || _isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AppBubbleSurface(
            isFab: true,
            borderRadius: AppRadius.pillAll,
            isEnabled: widget.onPressed != null,
            isPressed: _isPressed,
            boxShadow: AppShadows.fab,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppSpacing.fab,
                minHeight: AppSpacing.fab,
              ),
              child: Padding(
                padding: label == null
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    widget.child,
                    if (label != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        label,
                        style: AppText.button.copyWith(color: AppColors.white),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
