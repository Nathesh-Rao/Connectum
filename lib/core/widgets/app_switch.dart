import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The app's switch look. Colours live here only.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const _offTrackAlpha = 0.14;
  static const _offOutlineAlpha = 0.4;
  static const _outlineWidth = 1.5;
  static const _disabledOpacity = 0.4;

  static Color trackColor({required bool isOn}) => isOn
      ? AppColors.primary
      : AppColors.ink.withValues(alpha: _offTrackAlpha);

  static Color thumbColor({required bool isOn}) =>
      isOn ? AppColors.white : AppColors.muted;

  static Color outlineColor({required bool isOn}) => isOn
      ? Colors.transparent
      : AppColors.muted.withValues(alpha: _offOutlineAlpha);

  @override
  Widget build(BuildContext context) {
    final isOn = value;
    final isEnabled = onChanged != null;
    return Opacity(
      opacity: isEnabled ? 1 : _disabledOpacity,
      child: Switch(
        value: isOn,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        trackColor: WidgetStatePropertyAll(trackColor(isOn: isOn)),
        thumbColor: WidgetStatePropertyAll(thumbColor(isOn: isOn)),
        trackOutlineColor: WidgetStatePropertyAll(outlineColor(isOn: isOn)),
        trackOutlineWidth: const WidgetStatePropertyAll(_outlineWidth),
      ),
    );
  }
}
