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
      Color.alphaBlend(solid.withValues(alpha: 0.13), AppColors.white);

  Color get tintStrong =>
      Color.alphaBlend(solid.withValues(alpha: 0.20), AppColors.white);
}

/// The default palette of the notification icons and priority pills, by
/// meaning.
class AppTones {
  AppTones._();

  static const red = AppTone(Color(0xFFC62828), Color(0xFF8E1B1B));
  static const green = AppTone(Color(0xFF15803D), Color(0xFF115E2D));
  static const blue = AppTone(AppColors.primaryBright, AppColors.primaryStrong);
  static const violet = AppTone(AppColors.violet, AppColors.violetStrong);
  static const purple = AppTone(AppColors.purple, Color(0xFF4A2897));
  static const teal = AppTone(Color(0xFF0F766E), Color(0xFF0B5651));
  static const indigo = AppTone(AppColors.primaryStrong, Color(0xFF001F5C));

  /// The primary as a tone: the soft style of a main action.
  static const primary = AppTone(
    AppColors.primaryBright,
    AppColors.primaryStrong,
  );
  static const slate = AppTone(Color(0xFF475569), Color(0xFF334155));
}
