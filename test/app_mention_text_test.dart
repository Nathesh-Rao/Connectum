import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/utils/mention_text.dart';
import 'package:connectum/core/widgets/app_mention_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mentions are coloured bold text with no background', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppMentionText(
          text: 'hi @ann @me @zed',
          style: TextStyle(fontSize: 14),
          people: MentionPeople(me: 'me', names: {'ann': 'Ann'}),
        ),
      ),
    );
    final root = tester.widget<RichText>(find.byType(RichText).last).text;
    final spans = <TextSpan>[];
    root.visitChildren((s) {
      if (s is TextSpan) spans.add(s);
      return true;
    });
    TextSpan tag(String text) => spans.firstWhere((s) => s.text == text);
    final ann = tag('@Ann').style!;
    final me = tag('@me').style!;
    expect(ann.color, AppColors.mention);
    expect(ann.fontWeight, FontWeight.w600);
    expect(me.color, AppColors.mentionMe);
    expect(me.fontWeight, FontWeight.w700);
    expect(ann.backgroundColor, isNull);
    expect(me.backgroundColor, isNull);
    expect(me.decoration, TextDecoration.underline);
    expect(ann.decoration, isNull);
    expect(spans.any((s) => (s.text ?? '').contains('@zed')), isTrue);
  });

  test('mention colours read on every bubble and differ from sender inks', () {
    double ratio(Color a, Color b) {
      final l = [a.computeLuminance(), b.computeLuminance()]..sort();
      return (l[1] + 0.05) / (l[0] + 0.05);
    }

    for (final bubble in [
      AppColors.bubbleIn,
      AppColors.accentTint,
      AppColors.peach,
    ]) {
      expect(ratio(AppColors.mention, bubble), greaterThanOrEqualTo(4.5));
      expect(ratio(AppColors.mentionMe, bubble), greaterThanOrEqualTo(4.5));
    }
    for (final ink in AppColors.senderInks) {
      final hsl = HSLColor.fromColor(ink);
      expect(
        hsl.hue < 180 || hsl.hue > 260,
        isTrue,
        reason: 'sender ink $ink is blue-ish',
      );
    }
  });
}
