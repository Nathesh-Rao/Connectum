import 'package:connectum/core/theme/app_chart_colors.dart';
import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_tones.dart';
import 'package:connectum/core/utils/avatar_palette.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  double ratio(Color a, Color b) => AvatarPalette.contrast(a, b);

  void atLeast(double min, Color fg, Color bg, String name) {
    expect(ratio(fg, bg), greaterThanOrEqualTo(min), reason: name);
  }

  test('text on white and on the subtle panel fill', () {
    for (final bg in [AppColors.white, AppColors.surfaceSubtle]) {
      atLeast(4.5, AppColors.ink, bg, 'ink');
      atLeast(4.5, AppColors.muted, bg, 'muted');
      atLeast(4.5, AppColors.cardMuted, bg, 'cardMuted');
      atLeast(4.5, AppColors.primary, bg, 'primary text');
      atLeast(4.5, AppColors.error, bg, 'error');
    }
    atLeast(4.5, AppColors.muted, AppColors.fill, 'muted on fill');
    atLeast(4.5, AppColors.muted, AppColors.bubbleIn, 'muted on bubbleIn');
  });

  test('white on filled colours', () {
    atLeast(6.5, AppColors.white, AppColors.primary, 'primary');
    atLeast(4.5, AppColors.white, AppColors.purple, 'purple');
    atLeast(4.5, AppColors.white, AppColors.error, 'error');
    atLeast(4.5, AppColors.white, AppColors.primaryStrong, 'primaryStrong');
  });

  test('label on each tint', () {
    for (final tint in [
      AppColors.primarySoft,
      AppColors.primaryTint,
      AppColors.primaryTintStrong,
    ]) {
      atLeast(4.5, AppColors.primaryStrong, tint, 'primaryStrong');
      atLeast(4.5, AppColors.primary, tint, 'primary');
    }
    atLeast(4.5, AppColors.violetStrong, AppColors.violetTint, 'violet');
    atLeast(4.5, AppColors.yesText, AppColors.yesFill, 'yes');
    atLeast(4.5, AppColors.noText, AppColors.noFill, 'no');
    for (final t in [
      AppTones.red,
      AppTones.green,
      AppTones.blue,
      AppTones.violet,
      AppTones.purple,
      AppTones.teal,
      AppTones.indigo,
      AppTones.primary,
      AppTones.slate,
    ]) {
      atLeast(4.5, t.strong, t.tint, 'tone strong on tint ${t.solid}');
      atLeast(4.5, t.strong, t.tintStrong, 'tone strong on strong tint');
      atLeast(3, t.solid, t.tint, 'tone solid on tint ${t.solid}');
    }
  });

  test('the selected nav label (purple) reads 4.5:1 on white and the tint', () {
    atLeast(4.5, AppColors.purple, AppColors.white, 'purple on white');
    atLeast(4.5, AppColors.purple, AppColors.violetTint, 'purple on tint');
    atLeast(
      4.5,
      AppColors.violetStrong,
      AppColors.violetTint,
      'strong on tint',
    );
  });

  test('primaryBright icons read 3:1 on white and on the subtle fill', () {
    atLeast(3, AppColors.primaryBright, AppColors.white, 'white');
    atLeast(3, AppColors.primaryBright, AppColors.surfaceSubtle, 'subtle');
    atLeast(3, AppColors.primaryBright, AppColors.primaryTint, 'tint');
  });

  test('mentions and sender names read on every bubble', () {
    for (final bg in [
      AppColors.bubbleIn,
      AppColors.bubbleOut,
      AppColors.primaryTintStrong,
    ]) {
      atLeast(4.5, AppColors.mention, bg, 'mention');
      atLeast(4.5, AppColors.mentionMe, bg, 'mentionMe');
    }
    for (final c in AppColors.senderInks) {
      atLeast(4.5, c, AppColors.bubbleIn, 'sender $c');
      final hue = HSLColor.fromColor(c).hue;
      expect(
        hue > 190 && hue < 245 && HSLColor.fromColor(c).saturation > 0.3,
        isFalse,
        reason: 'sender $c is too close to the mention blue',
      );
    }
  });

  test('every avatar colour', () {
    for (final h in AvatarPalette.hues) {
      final c = AvatarPalette.colorsOf(h);
      atLeast(4.5, c.foreground, c.background, h.name);
      atLeast(4.5, AppColors.white, c.foreground, '${h.name} white');
    }
    atLeast(
      4.5,
      AvatarPalette.neutral.foreground,
      AvatarPalette.neutral.background,
      'neutral',
    );
  });

  test('every chart series colour', () {
    for (final c in AppChartColors.series) {
      atLeast(3, c, AppColors.white, 'white $c');
      atLeast(3, c, AppColors.surfaceSubtle, 'subtle $c');
    }
  });
}
