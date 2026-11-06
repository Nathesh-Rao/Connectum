import 'package:flutter/painting.dart';

import '../theme/app_colors.dart';

/// The colours of an avatar: [foreground] for the letter or icon and a very
/// light [background] of the same hue.
class AvatarColors {
  const AvatarColors(this.foreground, this.background);

  final Color foreground;
  final Color background;
}

class AvatarHue {
  const AvatarHue(
    this.name,
    this.hue,
    this.foregroundSaturation,
    this.foregroundLightness,
  );

  final String name;
  final double hue;
  final double foregroundSaturation;
  final double foregroundLightness;
}

/// Picks the colours of an avatar from a name, the same on every device and
/// launch: first letter, last letter and length choose one of [hues].
class AvatarPalette {
  AvatarPalette._();

  static const double backgroundSaturation = 0.75;
  static const double backgroundLightness = 0.94;

  /// Well spaced and warm-brand friendly: no red (that is the error colour),
  /// no muddy yellow-green.
  static const hues = [
    AvatarHue('teal', 178, 0.45, 0.32),
    AvatarHue('emerald', 150, 0.50, 0.32),
    AvatarHue('olive', 98, 0.45, 0.32),
    AvatarHue('deep amber', 34, 0.90, 0.32),
    AvatarHue('clay', 18, 0.70, 0.40),
    AvatarHue('rose', 338, 0.85, 0.40),
    AvatarHue('magenta', 312, 0.75, 0.40),
    AvatarHue('plum', 290, 0.70, 0.40),
    AvatarHue('violet', 268, 0.60, 0.40),
    AvatarHue('blue-violet', 246, 0.60, 0.40),
    AvatarHue('slate blue', 214, 0.65, 0.36),
    AvatarHue('sky cyan', 195, 0.80, 0.32),
  ];

  static const neutral = AvatarColors(AppColors.avatarText, AppColors.avatarBg);

  static int indexOf(String name) {
    final runes = name.trim().toLowerCase().runes.toList();
    if (runes.isEmpty) return -1;
    return (runes.first * 31 + runes.last * 17 + runes.length * 13) %
        hues.length;
  }

  static AvatarColors fromName(String name) {
    final index = indexOf(name);
    if (index < 0) return neutral;
    return colorsOf(hues[index]);
  }

  static AvatarColors colorsOf(AvatarHue hue) => AvatarColors(
    HSLColor.fromAHSL(
      1,
      hue.hue,
      hue.foregroundSaturation,
      hue.foregroundLightness,
    ).toColor(),
    HSLColor.fromAHSL(
      1,
      hue.hue,
      backgroundSaturation,
      backgroundLightness,
    ).toColor(),
  );

  /// WCAG contrast ratio of two opaque colours.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}
