import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// A solid colour, its tint (the solid at 13 % over white), a stronger tint
/// (20 %) and a darker shade of the same hue for text on the tints. The solid
/// reads at least 3:1 on its own tint; [strong] reads at least 4.5:1 on both
/// tints.
class AppTone {
  const AppTone(this.solid, this.strong);

  final Color solid;
  final Color strong;

  Color get tint =>
      Color.alphaBlend(solid.withValues(alpha: 0.13), AppColors.background);

  Color get tintStrong =>
      Color.alphaBlend(solid.withValues(alpha: 0.20), AppColors.background);
}

/// The default palette of the notification icons and priority pills, by
/// meaning.
class AppTones {
  AppTones._();

  static const red = AppTone(Color(0xFFC62828), Color(0xFF8E1B1B));
  static const green = AppTone(Color(0xFF15803D), Color(0xFF115E2D));
  static const blue = AppTone(Color(0xFF1A5FB4), Color(0xFF124585));
  static const orange = AppTone(Color(0xFFB45309), Color(0xFF8A3F08));
  static const purple = AppTone(Color(0xFF7C3AED), Color(0xFF5B21B6));
  static const teal = AppTone(Color(0xFF0F766E), Color(0xFF0B5651));
  static const indigo = AppTone(Color(0xFF4F46E5), Color(0xFF3730A3));

  /// The primary (orange) as a tone: the soft style of a main action.
  static const primary = AppTone(AppColors.accent, AppColors.accentInk);
  static const slate = AppTone(Color(0xFF475569), Color(0xFF334155));
}
