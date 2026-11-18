import 'sv_engine.dart';
import 'sv_values.dart';

/// One KPI card. [tone] is `brand`, `green`, `waiting` or `red`; [icon] the
/// web's icon word.
class SvKpiTile {
  const SvKpiTile({
    required this.id,
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.hasDecimals = false,
    this.sub = '',
  });

  final String id;
  final String label;
  final num value;
  final bool hasDecimals;
  final String icon;
  final String tone;

  /// A small line under the value (`avg 12.5`, `40% of the rows`).
  final String sub;
}

/// The web's `definedChart` result: groups biggest first (date columns in
/// date order), at most [SvInsights.definedMaxGroups] of them.
class SvDefinedChart {
  const SvDefinedChart({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.labels,
    required this.name,
    required this.values,
    required this.more,
  });

  final String type;
  final String title;
  final String subtitle;
  final List<String> labels;

  /// The series name (`SUM Qty`).
  final String name;
  final List<num> values;

  /// Groups left out because of the cap.
  final int more;
}

enum SvChartKind { bar, donut, line }

enum SvChartAgg { count, sum, avg }

enum SvDateBucket { auto, month, day }

/// What a chart is asked to show: rows grouped by [groupKey] and counted, or
/// summed or averaged over the number column [valueKey].
class SvChartSpec {
  const SvChartSpec({
    required this.groupKey,
    this.agg = SvChartAgg.count,
    this.valueKey,
    this.bucket = SvDateBucket.auto,
  });

  final String groupKey;
  final SvChartAgg agg;
  final String? valueKey;
  final SvDateBucket bucket;

  @override
  bool operator ==(Object other) =>
      other is SvChartSpec &&
      other.groupKey == groupKey &&
      other.agg == agg &&
      other.valueKey == valueKey &&
      other.bucket == bucket;

  @override
  int get hashCode => Object.hash(groupKey, agg, valueKey, bucket);
}

/// One bar, slice or point. [colorIndex] is the palette position (-1 for
/// "Others"); the same value always gets the same one.
class SvChartPoint {
  const SvChartPoint(this.label, this.value, this.count, this.colorIndex);

  final String label;
  final double value;

  /// Rows behind the point.
  final int count;
  final int colorIndex;
}

class SvChartData {
  const SvChartData({
    required this.points,
    required this.isDate,
    required this.unit,
    required this.subtitle,
    this.omitted = 0,
  });

  final List<SvChartPoint> points;
  final bool isDate;

  /// `Rows`, `Sum of Qty`, ...
  final String unit;
  final String subtitle;

  /// Older date buckets left out because of the cap.
  final int omitted;

  bool get isEmpty => points.isEmpty;
  double get total => points.fold(0, (a, p) => a + p.value);
  double get maxValue => points.fold(0, (a, p) => p.value > a ? p.value : a);
}

/// KPI and chart numbers over the rows that pass the search and filters.
/// Pure functions on an [EngineTable] and row positions, like [SvEngine].
class SvInsights {
  SvInsights._();

  static const definedMaxGroups = 40;
  static const maxCategories = 24;
  static const others = 'Others';
  static const emptyLabel = '(empty)';

  static const _tones = ['brand', 'green', 'waiting'];
  static const _aggIcons = {
    'sum': 'functions',
    'avg': 'avg_pace',
    'min': 'arrow_downward',
    'max': 'arrow_upward',
    'count': 'tag',
  };

  // ---- the web's defined cards and charts (vectors) ----------------------

  /// `definedCards`: per definition `{caption, agg, column}`, the value is the
  /// aggregate over [rows]; counting needs no column; a definition whose
  /// column is missing is skipped; tones cycle brand, green, waiting.
  static List<SvKpiTile> definedCards(
    EngineTable t,
    List<int> rows,
    List<Map<String, Object?>> defs,
  ) {
    final out = <SvKpiTile>[];
    for (var i = 0; i < defs.length; i++) {
      final d = defs[i];
      final agg = '${d['agg'] ?? 'count'}';
      final column = '${d['column'] ?? ''}';
      final isRows = agg == 'count' && column.isEmpty;
      if (!isRows && t.col(column) == null) continue;
      final value = isRows
          ? rows.length
          : SvEngine.aggregate(t, rows, column, agg);
      out.add(
        SvKpiTile(
          id: 'kpi:$i',
          label: '${d['caption'] ?? ''}',
          value: value,
          hasDecimals: agg != 'count',
          tone: _tones[i % _tones.length],
          icon: _aggIcons[agg] ?? 'tag',
        ),
      );
    }
    return out;
  }

  /// `definedChart`: group [rows] by `groupBy`, aggregate per group, date
  /// columns in date order else biggest first, at most [definedMaxGroups].
  static SvDefinedChart? definedChart(
    EngineTable t,
    List<int> rows,
    Map<String, Object?> def,
  ) {
    final groupKey = '${def['groupBy'] ?? ''}';
    final group = t.col(groupKey);
    if (group == null) return null;
    final agg = '${def['agg'] ?? 'count'}';
    final column = '${def['column'] ?? ''}';
    final measure = t.col(column);
    final isCount = agg == 'count' || measure == null;
    final byGroup = <String, List<int>>{};
    for (final r in rows) {
      final s = SvValues.plain(t.rows[r][groupKey]).trim();
      byGroup.putIfAbsent(s.isEmpty ? emptyLabel : s, () => []).add(r);
    }
    var entries = [
      for (final e in byGroup.entries)
        (
          label: e.key,
          value: isCount
              ? e.value.length
              : SvEngine.aggregate(t, e.value, column, agg),
          rows: e.value,
        ),
    ];
    if (group.type == EngineType.date) {
      int at(List<int> rs) {
        for (final r in rs) {
          final ms = SvValues.toTime(t.rows[r][groupKey]);
          if (ms != null) return ms;
        }
        return 1 << 52;
      }

      entries.sort((a, b) => at(a.rows).compareTo(at(b.rows)));
    } else {
      final indexed = [for (final (i, e) in entries.indexed) (i, e)];
      indexed.sort((a, b) {
        final c = b.$2.value.compareTo(a.$2.value);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
      entries = [for (final p in indexed) p.$2];
    }
    final more = entries.length > definedMaxGroups
        ? entries.length - definedMaxGroups
        : 0;
    final shown = entries.take(definedMaxGroups).toList();
    final groupLabel = _title(group.label);
    final word = isCount
        ? 'Rows'
        : '${agg.toUpperCase()} ${_title(measure.label)}';
    return SvDefinedChart(
      type: '${def['chart'] ?? 'bar'}',
      title: '${def['caption'] ?? ''}',
      subtitle: '$word by $groupLabel',
      labels: [for (final e in shown) e.label],
      name: word,
      values: [for (final e in shown) e.value],
      more: more,
    );
  }

  static String _title(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ---- numbers -----------------------------------------------------------

  /// 1234567.5 as `1,234,567.5`; whole numbers have no decimals, others at
  /// most two. No `intl`.
  static String format(num v, {int maxDecimals = 2}) {
    if (!v.isFinite) return '—';
    final neg = v < 0;
    final abs = v.abs();
    var s = abs.toStringAsFixed(maxDecimals);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    final parts = s.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${neg ? '-' : ''}$whole${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  /// min, max, sum, avg or count of [key] over [rows] (the engine's rule).
  static num stat(EngineTable t, List<int> rows, String key, String agg) =>
      SvEngine.aggregate(t, rows, key, agg);

  // ---- the KPI sheet -----------------------------------------------------

  /// The default cards: **Rows** (with `of N` when the rows are filtered), the
  /// top three values of the status column with their share, and a total
  /// card (with `avg X`) for the first two measure columns. The rules are the
  /// web's auto cards (`kpiCards`), applied to a structure's rows.
  static List<SvKpiTile> kpis(
    EngineTable t,
    List<int> rows, {
    required int loaded,
    String? statusKey,
    List<String> numberKeys = const [],
  }) {
    final out = <SvKpiTile>[
      SvKpiTile(
        id: 'rows',
        label: 'Records',
        value: rows.length,
        icon: 'tag',
        tone: 'brand',
        sub: rows.length == loaded ? '' : 'of ${format(loaded)}',
      ),
    ];
    if (statusKey != null && t.col(statusKey) != null) {
      final counts = <String, int>{};
      for (final r in rows) {
        final s = SvValues.plain(t.rows[r][statusKey]).trim();
        if (s.isEmpty) continue;
        counts[s] = (counts[s] ?? 0) + 1;
      }
      final top = counts.entries.toList()
        ..sort((a, b) {
          final c = b.value.compareTo(a.value);
          return c != 0 ? c : a.key.compareTo(b.key);
        });
      for (final e in top.take(3)) {
        final w = e.key.toLowerCase();
        final isBad = RegExp(r'declin|reject|cancel|fail').hasMatch(w);
        final isWait = RegExp(r'wait|pending|open|review').hasMatch(w);
        out.add(
          SvKpiTile(
            id: 'status:${e.key}',
            label: e.key,
            value: e.value,
            icon: isBad
                ? 'cancel'
                : isWait
                ? 'schedule'
                : 'check_circle',
            tone: isBad
                ? 'red'
                : isWait
                ? 'waiting'
                : 'green',
            sub: '${(e.value * 100 / rows.length).round()}% of the records',
          ),
        );
      }
    }
    for (final key in numberKeys.take(2)) {
      final col = t.col(key);
      if (col == null) continue;
      final n = rows
          .where((r) => SvValues.toNum(t.rows[r][key]) != null)
          .length;
      out.add(
        SvKpiTile(
          id: 'sum:$key',
          label: '${col.label}, total',
          value: SvEngine.aggregate(t, rows, key, 'sum'),
          hasDecimals: true,
          icon: 'functions',
          tone: 'green',
          sub: n == 0
              ? ''
              : 'avg ${format(SvEngine.aggregate(t, rows, key, 'avg'))}',
        ),
      );
    }
    return out;
  }

  // ---- the charts sheet --------------------------------------------------

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// The day bucket is used when every date falls in 31 days or fewer.
  static SvDateBucket bucketFor(
    EngineTable t,
    List<int> rows,
    String key, [
    SvDateBucket wanted = SvDateBucket.auto,
  ]) {
    if (wanted != SvDateBucket.auto) return wanted;
    int? lo;
    int? hi;
    for (final r in rows) {
      final ms = SvValues.toTime(t.rows[r][key]);
      if (ms == null) continue;
      if (lo == null || ms < lo) lo = ms;
      if (hi == null || ms > hi) hi = ms;
    }
    if (lo == null || hi == null) return SvDateBucket.month;
    return hi - lo <= const Duration(days: 31).inMilliseconds
        ? SvDateBucket.day
        : SvDateBucket.month;
  }

  /// A palette position per distinct value of [key], in the order of the
  /// sorted values over every loaded row, so a value keeps its colour when the
  /// filter changes.
  static Map<String, int> colorIndexes(EngineTable t, String key) {
    final seen = <String>{};
    for (final row in t.rows) {
      final s = SvValues.plain(row[key]).trim();
      seen.add(s.isEmpty ? emptyLabel : s);
    }
    final sorted = seen.toList()
      ..sort((a, b) => SvEngine.compareText(a.toLowerCase(), b.toLowerCase()));
    return {for (final (i, s) in sorted.indexed) s: i};
  }

  static SvChartData chart(
    EngineTable t,
    List<int> rows,
    SvChartSpec spec, {
    int paletteSize = 8,
  }) {
    final group = t.col(spec.groupKey);
    final measure = spec.valueKey == null ? null : t.col(spec.valueKey!);
    final agg = measure == null ? SvChartAgg.count : spec.agg;
    final unit = agg == SvChartAgg.count
        ? 'Records'
        : '${agg == SvChartAgg.sum ? 'Sum' : 'Average'} of ${measure!.label}';
    final subtitle = group == null ? unit : '$unit by ${group.label}';
    if (group == null) {
      return SvChartData(
        points: const [],
        isDate: false,
        unit: unit,
        subtitle: subtitle,
      );
    }
    double valueOf(List<int> rs) => switch (agg) {
      SvChartAgg.count => rs.length.toDouble(),
      SvChartAgg.sum => SvEngine.aggregate(
        t,
        rs,
        spec.valueKey!,
        'sum',
      ).toDouble(),
      SvChartAgg.avg => SvEngine.aggregate(
        t,
        rs,
        spec.valueKey!,
        'avg',
      ).toDouble(),
    };

    if (group.type == EngineType.date) {
      final bucket = bucketFor(t, rows, spec.groupKey, spec.bucket);
      final buckets = <int, List<int>>{};
      for (final r in rows) {
        final ms = SvValues.toTime(t.rows[r][spec.groupKey]);
        if (ms == null) continue;
        final d = DateTime.fromMillisecondsSinceEpoch(ms);
        final k = bucket == SvDateBucket.month
            ? d.year * 100 + d.month
            : d.year * 10000 + d.month * 100 + d.day;
        buckets.putIfAbsent(k, () => []).add(r);
      }
      final keys = buckets.keys.toList()..sort();
      final omitted = keys.length > maxCategories
          ? keys.length - maxCategories
          : 0;
      final shown = keys.skip(omitted).toList();
      return SvChartData(
        points: [
          for (final (i, k) in shown.indexed)
            SvChartPoint(
              _bucketLabel(k, bucket),
              valueOf(buckets[k]!),
              buckets[k]!.length,
              i % paletteSize,
            ),
        ],
        isDate: true,
        unit: unit,
        subtitle: bucket == SvDateBucket.month
            ? '$subtitle (by month)'
            : '$subtitle (by day)',
        omitted: omitted,
      );
    }

    final groups = <String, List<int>>{};
    for (final r in rows) {
      final s = SvValues.plain(t.rows[r][spec.groupKey]).trim();
      groups.putIfAbsent(s.isEmpty ? emptyLabel : s, () => []).add(r);
    }
    final colors = colorIndexes(t, spec.groupKey);
    final entries =
        [for (final (i, e) in groups.entries.indexed) (i, e.key, e.value)]
          ..sort((a, b) {
            final c = valueOf(b.$3).compareTo(valueOf(a.$3));
            return c != 0 ? c : a.$1.compareTo(b.$1);
          });
    final points = <SvChartPoint>[];
    for (final e in entries.take(maxCategories)) {
      points.add(
        SvChartPoint(
          e.$2,
          valueOf(e.$3),
          e.$3.length,
          (colors[e.$2] ?? 0) % paletteSize,
        ),
      );
    }
    if (entries.length > maxCategories) {
      final rest = <int>[for (final e in entries.skip(maxCategories)) ...e.$3];
      points.add(SvChartPoint(others, valueOf(rest), rest.length, -1));
    }
    return SvChartData(
      points: points,
      isDate: false,
      unit: unit,
      subtitle: subtitle,
    );
  }

  static String _bucketLabel(int k, SvDateBucket bucket) {
    if (bucket == SvDateBucket.month) {
      return '${_months[k % 100 - 1]} ${k ~/ 100}';
    }
    final month = (k ~/ 100) % 100;
    return '${_months[month - 1]} ${k % 100}';
  }

  /// The kind a chart starts as when none is picked (the web's `compareChart`):
  /// a line for a date with at least three buckets, a donut for six groups or
  /// fewer, else bars.
  static SvChartKind defaultKind(SvChartData d) {
    if (d.isDate && d.points.length >= 3) return SvChartKind.line;
    if (!d.isDate && d.points.length <= 6) return SvChartKind.donut;
    return SvChartKind.bar;
  }
}
