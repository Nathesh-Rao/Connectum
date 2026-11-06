import 'package:connectum/core/utils/avatar_palette.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same name gives the same colours, ignoring case and spaces', () {
    final a = AvatarPalette.fromName('Priya Sharma');
    final b = AvatarPalette.fromName('  priya sharma ');
    expect(b.foreground, a.foreground);
    expect(b.background, a.background);
  });

  test('unicode and emoji names work, an empty name is neutral', () {
    for (final n in ['अर्जुन', '李雷', '😀 party', 'Éva', 'a']) {
      final i = AvatarPalette.indexOf(n);
      expect(i, inInclusiveRange(0, AvatarPalette.hues.length - 1));
    }
    expect(
      AvatarPalette.fromName('').foreground,
      AvatarPalette.neutral.foreground,
    );
    expect(
      AvatarPalette.fromName('   ').background,
      AvatarPalette.neutral.background,
    );
  });

  test('every hue reads at 4.5:1 or better', () {
    for (final h in AvatarPalette.hues) {
      final c = AvatarPalette.colorsOf(h);
      final ratio = AvatarPalette.contrast(c.foreground, c.background);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: h.name);
    }
  });

  test('white on every foreground reads at 4.5:1 or better', () {
    for (final h in AvatarPalette.hues) {
      final c = AvatarPalette.colorsOf(h);
      final ratio = AvatarPalette.contrast(
        const Color(0xFFFFFFFF),
        c.foreground,
      );
      expect(ratio, greaterThanOrEqualTo(4.5), reason: h.name);
    }
  });

  test('foreground lightness stays in the deep range', () {
    for (final h in AvatarPalette.hues) {
      expect(h.foregroundLightness, inInclusiveRange(0.32, 0.40));
    }
  });

  test('names spread over several hues', () {
    const names = [
      'Priya Sharma',
      'Arjun',
      'Meera Nair',
      'Rahul',
      'Sana Khan',
      'Tom',
      'Ana Lopez',
      'Wei Chen',
      'Omar',
      'Zoe',
      'Billing Team',
      'Support',
      'Ticket #12: Printer',
      'Ops',
      'Leela',
      'Dev Patel',
    ];
    final used = {for (final n in names) AvatarPalette.indexOf(n)};
    expect(used.length, greaterThanOrEqualTo(6));
  });
}
