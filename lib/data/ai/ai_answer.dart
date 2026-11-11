import '../../core/widgets/app_chart/app_chart_data.dart';

/// One piece of an answer: Markdown text, or a chart read from a ` ```chart `
/// block.
class AiAnswerPart {
  const AiAnswerPart.text(String this.text) : chart = null;
  const AiAnswerPart.chart(AppChartData this.chart) : text = null;

  final String? text;
  final AppChartData? chart;
}

/// An answer split into its text and its charts. A chart block that does not
/// parse, and one still open (a half-arrived answer), shows nothing, never
/// raw JSON. Other code fences stay in the text.
class AiAnswer {
  AiAnswer._();

  static final _closed = RegExp(
    r'```[ \t]*chart\b[^\n]*\n([\s\S]*?)```',
    caseSensitive: false,
  );
  static final _open = RegExp(
    r'```[ \t]*chart\b[^\n]*(?:\n[\s\S]*)?$',
    caseSensitive: false,
  );

  static List<AiAnswerPart> parts(String source) {
    final out = <AiAnswerPart>[];
    void addText(String raw) {
      final t = raw.replaceAll(_open, '').trim();
      if (t.isNotEmpty) out.add(AiAnswerPart.text(t));
    }

    var at = 0;
    for (final m in _closed.allMatches(source)) {
      addText(source.substring(at, m.start));
      final chart = AppChartData.parse(m.group(1)!);
      if (chart != null) out.add(AiAnswerPart.chart(chart));
      at = m.end;
    }
    addText(source.substring(at));
    return out;
  }

  /// The answer as plain text for a copy, a post and its preview: each chart
  /// as "Title (unit)" and "- label: value" lines, in place.
  static String plain(String source) => parts(source)
      .map((p) => p.chart?.toPlainText() ?? p.text!)
      .join('\n\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
