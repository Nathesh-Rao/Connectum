import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// One run of a sentence: plain text, or a value that stands out.
class HighlightPart {
  const HighlightPart(this.text, {this.isHighlighted = false});

  final String text;
  final bool isHighlighted;
}

/// A sentence with names that stand out. The sentence is a [template] with
/// `{key}` placeholders and the names are [values]; the names are put in
/// place, never searched for in the finished text. A `{key}` without a value
/// stays as written, and a value is used as it is (braces in a name are just
/// characters).
class AppHighlightText extends StatelessWidget {
  const AppHighlightText(
    this.template, {
    super.key,
    this.values = const {},
    this.style = AppText.readable,
    this.maxLines,
    this.textAlign,
  });

  final String template;
  final Map<String, String> values;
  final TextStyle style;
  final int? maxLines;
  final TextAlign? textAlign;

  static final _placeholder = RegExp(r'\{(\w+)\}');

  /// The runs of [template], in order, with [values] in place of their
  /// placeholders. An empty value adds no run.
  static List<HighlightPart> parts(
    String template,
    Map<String, String> values,
  ) {
    final out = <HighlightPart>[];
    var from = 0;
    for (final m in _placeholder.allMatches(template)) {
      final value = values[m.group(1)];
      if (value == null) continue;
      if (m.start > from) {
        out.add(HighlightPart(template.substring(from, m.start)));
      }
      if (value.isNotEmpty) out.add(HighlightPart(value, isHighlighted: true));
      from = m.end;
    }
    if (from < template.length) {
      out.add(HighlightPart(template.substring(from)));
    }
    return out;
  }

  /// The whole sentence as plain text, for the screen reader.
  static String plain(String template, Map<String, String> values) =>
      parts(template, values).map((p) => p.text).join();

  @override
  Widget build(BuildContext context) {
    final highlight = style.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
    );
    return Semantics(
      label: plain(template, values),
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            for (final p in parts(template, values))
              TextSpan(text: p.text, style: p.isHighlighted ? highlight : null),
          ],
        ),
        maxLines: maxLines,
        overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
        textAlign: textAlign,
      ),
    );
  }
}
