import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/mention_text.dart';

/// Message text with `@name` drawn as a tag, as on the web. A known person
/// is drawn as `@` and the display name (the username is the semantics
/// label); a tag of me is deeper blue, bold and underlined. No background: the blue
/// reads on both bubbles (incoming grey, outgoing blue). Anyone unknown stays the text it was typed
/// as. Used wherever message text shows: bubbles, quotes, the reply bar.
class AppMentionText extends StatelessWidget {
  const AppMentionText({
    super.key,
    required this.text,
    required this.style,
    required this.people,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle style;
  final MentionPeople people;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final runs = MentionText.split(text);
    if (runs.every((r) => r.user == null || !people.isKnown(r.user!))) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final r in runs)
            if (r.user != null && people.isKnown(r.user!))
              TextSpan(
                text: '@${people.nameOf(r.user!)}',
                semanticsLabel: '@${r.user}',
                style: people.isMe(r.user!)
                    ? style.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.mentionMe,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.mentionMe,
                        decorationThickness: 1,
                      )
                    : style.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.mention,
                      ),
              )
            else
              TextSpan(text: r.text),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
