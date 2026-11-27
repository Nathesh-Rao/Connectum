import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/utils/avatar_tint.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Color hsl(double h, double s, double l) =>
    HSLColor.fromAHSL(1, h, s, l).toColor();

void main() {
  const surface = AppColors.white;

  final photos = <String, List<Color?>>{
    'dark': [null, hsl(220, 0.6, 0.2), null, null, const Color(0xFF111111)],
    'light': [hsl(200, 0.7, 0.9), null, null, null, hsl(200, 0.7, 0.9)],
    'grey': [const Color(0xFF888888), const Color(0xFF222222), null, null],
    'strong red': [const Color(0xFFC62828)],
    'pale pink': [hsl(340, 0.55, 0.9)],
    'yellow': [hsl(55, 0.9, 0.5)],
    'yellow-green': [hsl(80, 0.8, 0.45)],
    'blue': [hsl(220, 0.8, 0.5)],
  };

  void expectUniform(Color c) {
    final h = HSLColor.fromColor(c);
    expect(h.saturation, inInclusiveRange(0.25, 0.35));
    expect(h.lightness, inInclusiveRange(0.56, 0.72));
    expect(
      AvatarTint.contrast(c, surface),
      greaterThanOrEqualTo(AvatarTint.minContrast),
    );
  }

  test('every photo gets a ring of the same weight', () {
    photos.forEach((name, swatches) {
      final c = AvatarTint.pickRing(swatches);
      // ignore: avoid_print
      print('$name -> #${c.toARGB32().toRadixString(16)} $c');
      expectUniform(c);
    });
  });

  test('every hue ends inside the band and visible', () {
    for (var h = 0; h < 360; h += 5) {
      expectUniform(AvatarTint.pickRing([hsl(h.toDouble(), 0.8, 0.5)]));
    }
  });

  test('the same hue gives the same ring whatever the photo saturation', () {
    final a = AvatarTint.pickRing([hsl(10, 0.95, 0.3)]);
    final b = AvatarTint.pickRing([hsl(10, 0.95, 0.8)]);
    expect(a, b);
  });

  test('the hue follows the photo', () {
    double hue(Color c) => HSLColor.fromColor(c).hue;
    final red = hue(AvatarTint.pickRing(photos['strong red']!));
    expect(red < 10 || red > 350, isTrue);
    expect(hue(AvatarTint.pickRing(photos['blue']!)), closeTo(220, 4));
  });

  test('a grey photo uses the primary hue at the same weight', () {
    final c = AvatarTint.pickRing(photos['grey']!);
    expectUniform(c);
    expect(
      HSLColor.fromColor(c).hue,
      closeTo(HSLColor.fromColor(AppColors.primary).hue, 4),
    );
  });

  test('yellow-green is a little darker than the base lightness', () {
    final c = AvatarTint.pickRing(photos['yellow-green']!);
    expect(
      HSLColor.fromColor(c).lightness,
      lessThan(AvatarTint.ringLightness - 0.03),
    );
  });
}
