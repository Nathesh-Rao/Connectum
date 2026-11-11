import 'package:flutter/painting.dart';

/// Series colours of a chart, in order: orange leads. Each reads at least 3:1
/// on the white and ivory cards.
class AppChartColors {
  AppChartColors._();

  static const orange = Color(0xFFEE5F0C);
  static const lilac = Color(0xFF8465D4);
  static const teal = Color(0xFF0E8A80);
  static const sky = Color(0xFF2A82C8);
  static const coral = Color(0xFFDC5247);
  static const yellow = Color(0xFFA98500);

  static const series = [orange, lilac, teal, sky, coral, yellow];

  /// Grid lines and the baseline.
  static const grid = Color(0xFFEEEBE8);
  static const baseline = Color(0xFFCFC9C4);
}
