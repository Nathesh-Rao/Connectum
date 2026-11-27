import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_tones.dart';

/// A bare icon action in a tone's strong colour, no disc. 44 dp to tap.
/// [onPressed] null means not tappable; [isDimmed] reads as waiting;
/// [isBusy] swaps the icon for a progress ring.
class AppTonalIconButton extends StatefulWidget {
  const AppTonalIconButton({
    super.key,
    required this.icon,
    required this.tone,
    required this.label,
    this.onPressed,
    this.isBusy = false,
    this.isDimmed = false,
  });

  static const double iconSize = 20;
  static const double busySize = 16;

  final IconData icon;
  final AppTone tone;
  final String label;
  final VoidCallback? onPressed;
  final bool isBusy;
  final bool isDimmed;

  @override
  State<AppTonalIconButton> createState() => _AppTonalIconButtonState();
}

class _AppTonalIconButtonState extends State<AppTonalIconButton> {
  bool _isPressed = false;

  void _set(bool value) {
    if (_isPressed != value) setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;
    final tap = widget.isBusy ? null : widget.onPressed;
    final ink = widget.isDimmed
        ? tone.strong.withValues(alpha: 0.8)
        : tone.strong;
    return Semantics(
      container: true,
      button: tap != null,
      enabled: tap != null,
      label: widget.isBusy ? 'Sending request' : widget.label,
      excludeSemantics: true,
      onTap: tap,
      child: Tooltip(
        message: widget.label,
        excludeFromSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          onTapDown: tap == null ? null : (_) => _set(true),
          onTapUp: tap == null ? null : (_) => _set(false),
          onTapCancel: tap == null ? null : () => _set(false),
          child: SizedBox(
            width: AppSpacing.minTapTarget,
            height: AppSpacing.minTapTarget,
            child: Center(
              child: AnimatedScale(
                scale: _isPressed ? 0.92 : 1,
                duration: AppDurations.fast,
                curve: AppCurves.out,
                child: widget.isBusy
                    ? SizedBox(
                        width: AppTonalIconButton.busySize,
                        height: AppTonalIconButton.busySize,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tone.strong,
                        ),
                      )
                    : Icon(
                        widget.icon,
                        size: AppTonalIconButton.iconSize,
                        color: ink,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
