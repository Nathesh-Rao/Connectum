import 'package:flutter/material.dart';

import 'package:connectum/core/widgets/widgets.dart';

/// One attach option: a 56 px tonal circle with an icon, no visible label.
class AttachCircleButton extends StatelessWidget {
  const AttachCircleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    this.onTap,
  });

  static const double diameter = 56;
  static const double iconSize = 24;
  static const double disabledOpacity = 0.4;
  static const double splashAlpha = 0.12;

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback? onTap;

  bool get _isEnabled => onTap != null;

  @override
  Widget build(BuildContext context) {
    final circle = Tooltip(
      message: label,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: TonalAccent.circle(accent),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkResponse(
            onTap: onTap,
            containedInkWell: true,
            highlightShape: BoxShape.circle,
            radius: diameter / 2,
            splashColor: accent.withValues(alpha: splashAlpha),
            highlightColor: accent.withValues(alpha: splashAlpha / 2),
            child: Icon(icon, size: iconSize, color: accent),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: _isEnabled,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: _isEnabled
          ? circle
          : Opacity(opacity: disabledOpacity, child: circle),
    );
  }
}
