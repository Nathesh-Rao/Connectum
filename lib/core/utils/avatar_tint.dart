import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:palette_generator/palette_generator.dart';

import '../log/app_log.dart';
import '../theme/app_colors.dart';
import '../widgets/avatar_image.dart';

/// The ring colour of a person's picture on an Inbox card: the hue of the
/// picture at one fixed saturation and lightness (same visual weight on every
/// card), the theme's primary hue for a grey photo. Read off the first frame, once per picture
/// address, and kept: scrolling never reads it again. Null when there is no
/// picture or the picture could not be read.
class AvatarTint {
  AvatarTint._();

  static const _side = 48;
  static const _colors = 12;
  static const _timeout = Duration(seconds: 5);

  static final _done = <String, Color?>{};
  static final _pending = <String, Future<Color?>>{};

  /// The colour already read for [picture]; null while unknown or when none
  /// could be read. [isKnown] tells those apart.
  static Color? peek(String? picture) => _done[picture];

  static bool isKnown(String? picture) =>
      picture == null || picture.isEmpty || _done.containsKey(picture);

  static Future<Color?> of(String? picture) {
    if (picture == null || picture.isEmpty) return Future.value();
    if (_done.containsKey(picture)) return Future.value(_done[picture]);
    return _pending[picture] ??= _read(picture).whenComplete(() {
      _pending.remove(picture);
    });
  }

  static Future<Color?> _read(String picture) async {
    Color? color;
    try {
      final provider = AvatarImages.providerFor(picture);
      if (provider != null) {
        final palette = await PaletteGenerator.fromImageProvider(
          ResizeImage(provider, width: _side, height: _side),
          maximumColorCount: _colors,
          timeout: _timeout,
        );
        color = pickRing([
          palette.vibrantColor?.color,
          palette.darkVibrantColor?.color,
          palette.lightVibrantColor?.color,
          palette.mutedColor?.color,
          palette.dominantColor?.color,
        ]);
      }
    } on Object catch (e, st) {
      AppLog.e('avatar_tint', e, st);
    }
    _done[picture] = color;
    return color;
  }

  /// Every ring has the same weight: only the hue comes from the photo.
  static const ringSaturation = 0.30;
  static const ringLightness = 0.66;
  static const yellowGreenFrom = 50.0;
  static const yellowGreenTo = 100.0;
  static const yellowGreenDrop = 0.05;
  static const minSwatchSaturation = 0.15;
  static const minContrast = 1.8;
  static const maxNudge = 0.08;
  static const nudgeStep = 0.02;
  static const bandMinSaturation = 0.25;
  static const bandMaxSaturation = 0.35;
  static const bandMinLightness = 0.56;
  static const bandMaxLightness = 0.72;

  /// WCAG contrast ratio of two opaque colours.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// The ring colour from [swatches] (vibrant, dark vibrant, light vibrant,
  /// muted, dominant; nulls skipped). The hue of the first swatch with real
  /// colour is rebuilt at [ringSaturation] / [ringLightness] (a little darker
  /// for yellow-green), nudged darker, at most [maxNudge], until it has
  /// [minContrast] against [surface]. No swatch with real colour: the hue of
  /// [AppColors.primary] at the same weight.
  static Color pickRing(
    Iterable<Color?> swatches, {
    Color surface = AppColors.white,
  }) {
    var hue = HSLColor.fromColor(AppColors.primary).hue;
    for (final c in swatches) {
      if (c == null) continue;
      final hsl = HSLColor.fromColor(c);
      if (hsl.saturation < minSwatchSaturation) continue;
      hue = hsl.hue;
      break;
    }
    final isYellowGreen = hue >= yellowGreenFrom && hue <= yellowGreenTo;
    final start = ringLightness - (isYellowGreen ? yellowGreenDrop : 0);
    final floor = math.max(bandMinLightness, start - maxNudge);
    var lightness = start.clamp(bandMinLightness, bandMaxLightness);
    while (true) {
      final color = HSLColor.fromAHSL(
        1,
        hue,
        ringSaturation,
        lightness,
      ).toColor();
      if (contrast(color, surface) >= minContrast || lightness <= floor) {
        return color;
      }
      lightness = math.max(floor, lightness - nudgeStep);
    }
  }

  /// Forgets what was read (tests).
  static void reset() {
    _done.clear();
    _pending.clear();
  }
}
