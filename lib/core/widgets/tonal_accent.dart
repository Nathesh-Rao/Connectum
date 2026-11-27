import 'package:flutter/material.dart';

/// The tonal look shared by the Forms chips and the Attach circles: a 1px
/// border in the accent at [borderAlpha], and optionally a light accent fill.
class TonalAccent {
  TonalAccent._();

  static const double fillAlpha = 0.04;
  static const double borderAlpha = 0.25;

  static Border border(Color accent) => Border.fromBorderSide(
    BorderSide(color: accent.withValues(alpha: borderAlpha)),
  );

  static BoxDecoration circle(Color accent) => BoxDecoration(
    shape: BoxShape.circle,
    color: accent.withValues(alpha: fillAlpha),
    border: border(accent),
  );
}
