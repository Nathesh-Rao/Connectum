import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_chart/app_chart.dart';
import '../../../data/ai/ai_answer.dart';

final _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
final _heading = RegExp(r'^\s*#{1,6}\s+(.*)$');
final _bold = RegExp(r'\*\*(.+?)\*\*');

/// No markdown renderer is bundled: headings, bullets, numbered lines and
/// **bold** are drawn; anything else shows as plain text.
List<InlineSpan> aiSpans(String source) {
  final spans = <InlineSpan>[];
  final lines = source.trim().split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trimRight();
    final heading = _heading.firstMatch(line);
    final bullet = _bullet.firstMatch(line);
    if (heading != null) {
      spans.add(
        TextSpan(text: _plain(heading.group(1)!), style: AppText.bodyStrong),
      );
    } else if (bullet != null) {
      spans.add(const TextSpan(text: '•  '));
      spans.addAll(_inline(bullet.group(1)!));
    } else {
      spans.addAll(_inline(line));
    }
    if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
  }
  return spans;
}

String _plain(String s) => s.replaceAllMapped(_bold, (m) => m.group(1)!);

List<InlineSpan> _inline(String s) {
  final out = <InlineSpan>[];
  var at = 0;
  for (final m in _bold.allMatches(s)) {
    if (m.start > at) out.add(TextSpan(text: s.substring(at, m.start)));
    out.add(
      TextSpan(
        text: m.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    at = m.end;
  }
  if (at < s.length) out.add(TextSpan(text: s.substring(at)));
  return out;
}

/// The answer: each text part is one selectable block (so a long press
/// selects across headings and bullets) and each chart is drawn in place.
class AiRichText extends StatelessWidget {
  const AiRichText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final parts = AiAnswer.parts(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          if (parts[i].chart case final chart?)
            AppChart(chart, key: ValueKey('chart-$i'))
          else
            SelectableText.rich(
              TextSpan(
                style: AppText.body.copyWith(color: AppColors.ink),
                children: aiSpans(parts[i].text!),
              ),
            ),
        ],
      ],
    );
  }
}
