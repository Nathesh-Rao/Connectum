import 'dart:convert';
import 'dart:math' as math;

enum AppChartType { bar, column, line, donut }

class AppChartSeries {
  const AppChartSeries(this.name, this.values);

  final String name;

  /// One value per label; null where the model gave none (skipped).
  final List<double?> values;
}

/// A chart read from the JSON of a ` ```chart ` block, with the same
/// accepted formats and limits as the web (`aiFormat/chart.js`): 40 labels,
/// 6 series, label 60, series name 40, title 120, unit 24 characters.
class AppChartData {
  const AppChartData({
    required this.type,
    required this.title,
    required this.unit,
    required this.labels,
    required this.series,
  });

  final AppChartType type;
  final String title;
  final String unit;
  final List<String> labels;
  final List<AppChartSeries> series;

  bool get isMulti => series.length > 1;

  /// Reads [source], or null when it is not a usable chart.
  static AppChartData? parse(String source) {
    final Object? j;
    try {
      j = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (j is! Map) return null;
    final rawType = j['type'];
    final type = switch (rawType) {
      'bar' => AppChartType.bar,
      'column' => AppChartType.column,
      'line' => AppChartType.line,
      'donut' || 'pie' => AppChartType.donut,
      _ => AppChartType.bar,
    };
    var labels = <String>[];
    var series = <AppChartSeries>[];
    final rawSeries = j['series'];
    final rawLabels = j['labels'];
    final rawData = j['data'];
    if (rawSeries is List && rawSeries.isNotEmpty && rawLabels is List) {
      labels = [for (final l in rawLabels.take(40)) _str(l, 60)];
      series = [
        for (final s in rawSeries.take(6))
          AppChartSeries(_str(s is Map ? s['name'] : null, 40), [
            for (var i = 0; i < labels.length; i++)
              _num(
                s is Map && s['data'] is List && i < (s['data'] as List).length
                    ? (s['data'] as List)[i]
                    : null,
              ),
          ]),
      ];
    } else if (rawData is List) {
      final rows = <(String, double)>[];
      for (final d in rawData.take(40)) {
        final label = _str(d is Map ? (d['label'] ?? d['name']) : null, 60);
        final value = _num(d is Map ? d['value'] : null);
        if (label.isNotEmpty && value != null) rows.add((label, value));
      }
      labels = [for (final r in rows) r.$1];
      series = [
        AppChartSeries(_str(j['title'], 40), [for (final r in rows) r.$2]),
      ];
    }
    if (labels.isEmpty || !series.any((s) => s.values.any((v) => v != null))) {
      return null;
    }
    return AppChartData(
      type: type,
      title: _str(j['title'], 120),
      unit: _str(j['unit'], 24),
      labels: labels,
      series: series,
    );
  }

  static double? _num(Object? v) {
    final n = v is String ? double.tryParse(v.replaceAll(',', '').trim()) : v;
    if (n is! num) return null;
    final d = n.toDouble();
    return d.isFinite && d.abs() < 1e15 ? d : null;
  }

  static String _str(Object? v, int max) {
    final s = '${v ?? ''}';
    if (s.length <= max) return s;
    var end = max;
    final last = s.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return s.substring(0, end);
  }

  /// A value as the web shows it (`fmt`): thousands separators from 1,000
  /// (one decimal at most), else rounded to two decimals.
  static String format(double n) {
    if (n.abs() >= 1000) {
      final fixed = n.toStringAsFixed(1);
      final trimmed = fixed.endsWith('.0')
          ? fixed.substring(0, fixed.length - 2)
          : fixed;
      return trimmed.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
    }
    final r = (n * 100).round() / 100;
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }

  String _value(double v) => unit.isEmpty ? format(v) : '${format(v)} $unit';

  /// The chart as text, for a copy or a post: `Title (unit)`, then
  /// `- label: value` per row; a multi-series chart has a line per series
  /// name first.
  String toPlainText() {
    final out = <String>[];
    final head = title.isEmpty
        ? (unit.isEmpty ? '' : 'Chart ($unit)')
        : (unit.isEmpty ? title : '$title ($unit)');
    if (head.isNotEmpty) out.add(head);
    for (final s in series) {
      if (isMulti) out.add(s.name.isEmpty ? 'Series' : s.name);
      for (var i = 0; i < labels.length; i++) {
        final v = s.values[i];
        if (v != null) out.add('- ${labels[i]}: ${format(v)}');
      }
    }
    return out.join('\n');
  }

  /// "Bar chart: Title. Label 1: 10 unit, Label 2: 20 unit".
  String describe() {
    final kind = switch (type) {
      AppChartType.bar => 'Bar chart',
      AppChartType.column => 'Column chart',
      AppChartType.line => 'Line chart',
      AppChartType.donut => 'Donut chart',
    };
    final parts = <String>[];
    for (final s in series) {
      final rows = <String>[
        for (var i = 0; i < labels.length; i++)
          if (s.values[i] != null) '${labels[i]}: ${_value(s.values[i]!)}',
      ];
      parts.add(
        isMulti
            ? '${s.name.isEmpty ? 'Series' : s.name}. ${rows.join(', ')}'
            : rows.join(', '),
      );
    }
    return '$kind${title.isEmpty ? '' : ': $title'}. ${parts.join('. ')}';
  }

  /// Nice axis ticks that start at zero (or below it for negatives) and
  /// cover [min]..[max]: steps of 1, 2, 2.5, 5 or 10 times a power of ten,
  /// about [target] intervals. Never empty, never more than 12 ticks.
  static List<double> niceTicks(double min, double max, {int target = 4}) {
    var lo = math.min(0.0, min.isFinite ? min : 0);
    var hi = math.max(0.0, max.isFinite ? max : 0);
    if (hi == lo) hi = lo + 1;
    final raw = (hi - lo) / target;
    final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / exp;
    final nice = f <= 1
        ? 1
        : (f <= 2 ? 2 : (f <= 2.5 ? 2.5 : (f <= 5 ? 5 : 10)));
    final step = nice * exp;
    lo = (lo / step).floor() * step;
    hi = (hi / step).ceil() * step;
    final ticks = <double>[];
    for (var i = 0; i <= 12; i++) {
      final t = lo + i * step;
      ticks.add(double.parse(t.toStringAsPrecision(12)));
      if (t >= hi - step * 1e-9) break;
    }
    return ticks;
  }
}
