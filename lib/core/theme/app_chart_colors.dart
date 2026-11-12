import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Series colours of a chart, in order: the brand blue leads. Each reads at
/// least 3:1 on the white card and on the page background.
class AppChartColors {
  AppChartColors._();

  static const blue = AppColors.primaryBright;
  static const violet = Color(0xFF8465F0);
  static const cyan = Color(0xFF0892C8);
  static const indigo = AppColors.primaryStrong;
  static const teal = Color(0xFF0E8A80);
  static const rose = Color(0xFFD6336C);
  static const slate = Color(0xFF64748B);

  static const series = [blue, violet, cyan, indigo, teal, rose, slate];

  /// Grid lines and the baseline.
  static const grid = Color(0xFFE3EAF4);
  static const baseline = Color(0xFFB9C4D8);
}
