import 'sv_values.dart';

/// One column the engine reads: a key into each row, a label for chips and
/// the kind that picks the filter operators and the sort.
class EngineCol {
  const EngineCol(this.key, this.label, this.type);

  final String key;
  final String label;
  final EngineType type;
}

/// Rows as maps by column key. The engine never changes them.
class EngineTable {
  const EngineTable(this.columns, this.rows);

  final List<EngineCol> columns;
  final List<Map<String, Object?>> rows;

  EngineCol? col(String key) {
    for (final c in columns) {
      if (c.key == key) return c;
    }
    return null;
  }
}

/// The two reserved condition names of the "My team" and "Linked as" lines.
/// They ride in the list of conditions (so a saved view keeps them) but are
/// not columns: the server cuts the records by them, the engine skips them.
class SvTeamCols {
  SvTeamCols._();

  static const team = '__team';
  static const linked = '__linked';

  static bool isReserved(String col) => col == team || col == linked;
}

/// One filter condition. [value] is a String or number, a list (`in`) or a
/// `{from, to}` map (`between`).
class SvCondition {
  const SvCondition(this.col, this.op, [this.value]);

  final String col;
  final String op;
  final Object? value;

  @override
  bool operator ==(Object other) =>
      other is SvCondition &&
      other.col == col &&
      other.op == op &&
      _same(other.value, value);

  @override
  int get hashCode => Object.hash(col, op, _hash(value));

  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.entries.every((e) => b[e.key] == e.value);
    }
    return a == b;
  }

  static int _hash(Object? v) => v is List
      ? Object.hashAll(v)
      : v is Map
      ? Object.hashAll([for (final e in v.entries) Object.hash(e.key, e.value)])
      : v.hashCode;
}

/// A line of a grouped list: a group header, or one row under it.
class SvFlat {
  const SvFlat.group({
    required String this.group,
    required String this.path,
    required this.depth,
    required int this.count,
    required num this.sum,
    required bool this.open,
  }) : row = null;

  const SvFlat.row(int this.row, this.depth)
    : group = null,
      path = null,
      count = null,
      sum = null,
      open = null;

  final String? group;
  final String? path;
  final int depth;
  final int? count;
  final num? sum;
  final bool? open;
  final int? row;

  bool get isGroup => group != null;
}

/// Search, filter, sort, group and aggregate over an [EngineTable], returning
/// row positions. Pure functions: nothing is mutated, hidden columns are the
/// caller's to leave out of the table.
class SvEngine {
  SvEngine._();

  static const textOps = [
    'contains',
    'equals',
    'not',
    'starts',
    'empty',
    'filled',
  ];
  static const numberOps = [
    'eq',
    'ne',
    'gt',
    'gte',
    'lt',
    'lte',
    'between',
    'empty',
    'filled',
  ];
  static const dateOps = [
    'on',
    'after',
    'before',
    'between',
    'empty',
    'filled',
  ];
  static const boolOps = ['true', 'false'];
  static const _noValueOps = {'empty', 'filled', 'true', 'false'};

  /// The operators valid for a column kind.
  static List<String> opsFor(EngineType t) => switch (t) {
    EngineType.number => numberOps,
    EngineType.date => dateOps,
    EngineType.bool => boolOps,
    _ => textOps,
  };

  static String opLabel(String op) => switch (op) {
    'contains' => 'contains',
    'equals' => 'is',
    'not' => 'is not',
    'starts' => 'starts with',
    'empty' => 'is empty',
    'filled' => 'is filled',
    'in' => 'is any of',
    'eq' => '=',
    'ne' => '≠',
    'gt' => '>',
    'gte' => '≥',
    'lt' => '<',
    'lte' => '≤',
    'between' => 'between',
    'on' => 'on',
    'after' => 'after',
    'before' => 'before',
    'true' => 'is yes',
    'false' => 'is no',
    _ => op,
  };

  /// Whether a condition counts: it has a column and operator and, unless
  /// the operator needs none, a value (`in` needs one entry, `between` one
  /// end). An inactive condition is ignored, not "match nothing".
  static bool isActive(SvCondition c) {
    if (c.col.isEmpty || c.op.isEmpty) return false;
    if (_noValueOps.contains(c.op)) return true;
    final v = c.value;
    if (c.op == 'in') return v is List && v.isNotEmpty;
    if (c.op == 'between') {
      return v is Map &&
          (!SvValues.isBlank(v['from']) || !SvValues.isBlank(v['to']));
    }
    return !SvValues.isBlank(v);
  }

  /// Positions of the rows that pass the search and every active condition
  /// (AND), in table order. [searchIn] limits the search to those columns.
  static List<int> filter(
    EngineTable t, {
    String search = '',
    List<EngineCol>? searchIn,
    List<SvCondition> conditions = const [],
    DateTime? now,
  }) {
    final q = search.trim().toLowerCase();
    final cols = searchIn ?? t.columns;
    final active = [
      for (final c in conditions)
        if (isActive(c) && !SvTeamCols.isReserved(c.col)) c,
    ];
    final types = {for (final c in t.columns) c.key: c.type};
    final out = <int>[];
    for (var i = 0; i < t.rows.length; i++) {
      final row = t.rows[i];
      if (q.isNotEmpty &&
          !cols.any(
            (c) => SvValues.plain(row[c.key]).toLowerCase().contains(q),
          )) {
        continue;
      }
      var ok = true;
      for (final c in active) {
        if (!types.containsKey(c.col) ||
            !_matches(c, types[c.col]!, row[c.col], now)) {
          ok = false;
          break;
        }
      }
      if (ok) out.add(i);
    }
    return out;
  }

  static bool _matches(
    SvCondition c,
    EngineType type,
    Object? v,
    DateTime? now,
  ) {
    final op = c.op;
    switch (op) {
      case 'empty':
        return SvValues.plain(v).trim().isEmpty;
      case 'filled':
        return SvValues.plain(v).trim().isNotEmpty;
      case 'in':
        final s = SvValues.plain(v).toLowerCase();
        return (c.value! as List).any((e) => '$e'.toLowerCase() == s);
      case 'true':
        return const {'true', 'yes', '1'}.contains(_low(v));
      case 'false':
        return const {'false', 'no', '0'}.contains(_low(v));
      case 'contains' || 'equals' || 'not' || 'starts':
        final s = SvValues.plain(v).toLowerCase();
        final w = SvValues.plain(c.value).trim().toLowerCase();
        return switch (op) {
          'contains' => s.contains(w),
          'equals' => s == w,
          'not' => s != w,
          _ => s.startsWith(w),
        };
      case 'eq' || 'ne' || 'gt' || 'gte' || 'lt' || 'lte':
        final a = SvValues.toNum(v);
        final b = SvValues.toNum(c.value);
        if (a == null || b == null) return false;
        return switch (op) {
          'eq' => a == b,
          'ne' => a != b,
          'gt' => a > b,
          'gte' => a >= b,
          'lt' => a < b,
          _ => a <= b,
        };
      case 'on' || 'after' || 'before':
        final a = _day(v, now);
        final b = _day(c.value, now);
        if (a == null || b == null) return false;
        return switch (op) {
          'on' => a == b,
          'after' => a > b,
          _ => a < b,
        };
      case 'between':
        final range = c.value! as Map;
        if (type == EngineType.number) {
          final a = SvValues.toNum(v);
          if (a == null) return false;
          final from = SvValues.toNum(range['from']);
          final to = SvValues.toNum(range['to']);
          return (from == null || a >= from) && (to == null || a <= to);
        }
        final a = _day(v, now);
        if (a == null) return false;
        final from = _day(range['from'], now);
        final to = _day(range['to'], now);
        return (from == null || a >= from) && (to == null || a <= to);
    }
    return false;
  }

  static String _low(Object? v) => SvValues.plain(v).trim().toLowerCase();

  static int? _day(Object? v, DateTime? now) {
    if (v is String && v.trim().toLowerCase() == 'today') {
      return SvValues.dayOf((now ?? DateTime.now()).millisecondsSinceEpoch);
    }
    final ms = SvValues.toTime(v);
    return ms == null ? null : SvValues.dayOf(ms);
  }

  /// [rows] (positions) ordered by column [key]: numbers by value, dates by
  /// time, anything else by the lower-cased text, numeric-aware. Blanks go
  /// last in both directions and ties keep their order (a descending sort
  /// does not reverse them).
  static List<int> sort(
    EngineTable t,
    List<int> rows,
    String key,
    bool isAscending,
  ) {
    final col = t.col(key);
    if (col == null) return List.of(rows);
    final keyed = <_SortKey>[];
    for (var n = 0; n < rows.length; n++) {
      final v = t.rows[rows[n]][key];
      keyed.add(switch (col.type) {
        EngineType.number => _SortKey(rows[n], n, num: SvValues.toNum(v)),
        EngineType.date => _SortKey(
          rows[n],
          n,
          num: SvValues.toTime(v)?.toDouble(),
        ),
        _ => _SortKey(rows[n], n, text: _textKey(v)),
      });
    }
    keyed.sort((a, b) {
      if (a.isBlank != b.isBlank) return a.isBlank ? 1 : -1;
      if (a.isBlank) return a.n.compareTo(b.n);
      var c = a.num != null
          ? a.num!.compareTo(b.num!)
          : a.text!.compareTo(b.text!);
      if (!isAscending) c = -c;
      return c != 0 ? c : a.n.compareTo(b.n);
    });
    return [for (final k in keyed) k.row];
  }

  static _TextKey? _textKey(Object? v) {
    final s = SvValues.plain(v).trim().toLowerCase();
    return s.isEmpty ? null : _TextKey(s);
  }

  /// Numeric-aware, case-insensitive, accent-insensitive-first text order
  /// (`Item 2 < Item 9 < Item 10`). Locale-free: a letter with an accent
  /// sorts with its base letter, then by the accent.
  static int compareText(String a, String b) =>
      _TextKey(a).compareTo(_TextKey(b));

  static const _from = 'àáâãäåāçćčďèéêëēėęěìíîïīłñńňòóôõöøōřśšťùúûüūůýÿžźż';
  static const _to = 'aaaaaaacccdeeeeeeeeiiiiilnnnooooooorsstuuuuuuyyzzz';

  static String _fold(String s) {
    StringBuffer? b;
    for (var i = 0; i < s.length; i++) {
      final u = s.codeUnitAt(i);
      if (u < 128) {
        b?.writeCharCode(u);
        continue;
      }
      final k = _from.indexOf(s[i]);
      b ??= StringBuffer(s.substring(0, i));
      b.write(k < 0 ? s[i] : _to[k]);
    }
    return b?.toString() ?? s;
  }

  /// Groups [rows] by [keys] in order of first appearance and flattens the
  /// tree. A blank key is `(empty)`; each group holds its row count and the
  /// sum of [sumKey] (blanks add 0). [closed] holds paths (keys joined with
  /// U+001F) whose rows are hidden.
  static List<SvFlat> group(
    EngineTable t,
    List<int> rows,
    List<String> keys, {
    String? sumKey,
    Set<String> closed = const {},
  }) {
    final out = <SvFlat>[];
    void walk(List<int> list, int depth, String prefix) {
      if (depth == keys.length) {
        for (final r in list) {
          out.add(SvFlat.row(r, depth));
        }
        return;
      }
      final groups = <String, List<int>>{};
      for (final r in list) {
        final s = SvValues.plain(t.rows[r][keys[depth]]);
        groups.putIfAbsent(s.trim().isEmpty ? '(empty)' : s, () => []).add(r);
      }
      for (final e in groups.entries) {
        final path = prefix.isEmpty ? e.key : '$prefix\u001f${e.key}';
        final isOpen = !closed.contains(path);
        var sum = 0.0;
        if (sumKey != null) {
          for (final r in e.value) {
            sum += SvValues.toNum(t.rows[r][sumKey]) ?? 0;
          }
        }
        out.add(
          SvFlat.group(
            group: e.key,
            path: path,
            depth: depth,
            count: e.value.length,
            sum: sum,
            open: isOpen,
          ),
        );
        if (isOpen) walk(e.value, depth + 1, path);
      }
    }

    walk(rows, 0, '');
    return out;
  }

  /// `__rows` counts rows, `count` the filled cells, `sum/avg/min/max` run
  /// over the cells that read as numbers; an empty set gives 0.
  static num aggregate(EngineTable t, List<int> rows, String key, String agg) {
    if (key == '__rows' || agg == '__rows') return rows.length;
    if (agg == 'count') {
      return rows.where((r) => !SvValues.isBlank(t.rows[r][key])).length;
    }
    final nums = <double>[
      for (final r in rows) ?SvValues.toNum(t.rows[r][key]),
    ];
    if (nums.isEmpty) return 0;
    return switch (agg) {
      'sum' => nums.fold<double>(0, (a, b) => a + b),
      'avg' => nums.fold<double>(0, (a, b) => a + b) / nums.length,
      'min' => nums.reduce((a, b) => a < b ? a : b),
      'max' => nums.reduce((a, b) => a > b ? a : b),
      _ => 0,
    };
  }

  /// How a filter is edited: `choice` (pick from the distinct values; a
  /// text column with more than 60 of them is typed instead), `number`,
  /// `date` or `bool`.
  static String controlFor(EngineCol c, {int distinct = 0}) => switch (c.type) {
    EngineType.number => 'number',
    EngineType.date => 'date',
    EngineType.bool => 'bool',
    EngineType.text => distinct > 60 ? 'text' : 'choice',
    _ => 'text',
  };

  /// The text of a filter chip: `Qty: from 500`, `Kind: A, B +1`,
  /// `Name starts with al`, `OK is yes`.
  static String chipText(SvCondition c, String label) {
    final v = c.value;
    String range(Object? raw, String join) {
      final m = raw is Map ? raw : const {};
      final from = SvValues.plain(m['from']);
      final to = SvValues.plain(m['to']);
      if (from.isNotEmpty && to.isNotEmpty) return '$from $join $to';
      return from.isNotEmpty ? 'from $from' : 'up to $to';
    }

    switch (c.op) {
      case 'in':
        final l = [for (final e in v as List) '$e'];
        final shown = l.take(2).join(', ');
        return '$label: $shown${l.length > 2 ? ' +${l.length - 2}' : ''}';
      case 'between':
        return '$label: ${range(v, 'to')}';
      case 'contains' || 'equals' || 'not' || 'starts':
        return '$label ${opLabel(c.op)} ${SvValues.plain(v)}';
      case 'empty' || 'filled' || 'true' || 'false':
        return '$label ${opLabel(c.op)}';
      case 'eq' || 'ne' || 'gt' || 'gte' || 'lt' || 'lte':
        return '$label ${opLabel(c.op)} ${SvValues.plain(v)}';
      default:
        return '$label ${opLabel(c.op)} ${SvValues.plain(v)}';
    }
  }

  /// The date presets of the filter panel for [now]; the week runs Monday to
  /// Sunday. Keys: custom, today, yesterday, week, 7days, month, lastmonth,
  /// year; each `{from, to}` as `yyyy-mm-dd` (custom is empty).
  static Map<String, ({String from, String to})> rangeFor(DateTime now) {
    String f(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final today = DateTime(now.year, now.month, now.day);
    DateTime plus(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
    final monday = plus(today, -(today.weekday - 1));
    return {
      'custom': (from: '', to: ''),
      'today': (from: f(today), to: f(today)),
      'yesterday': (from: f(plus(today, -1)), to: f(plus(today, -1))),
      'week': (from: f(monday), to: f(plus(monday, 6))),
      '7days': (from: f(plus(today, -6)), to: f(today)),
      'month': (
        from: f(DateTime(now.year, now.month)),
        to: f(DateTime(now.year, now.month + 1, 0)),
      ),
      'lastmonth': (
        from: f(DateTime(now.year, now.month - 1)),
        to: f(DateTime(now.year, now.month, 0)),
      ),
      'year': (from: f(DateTime(now.year)), to: f(DateTime(now.year, 12, 31))),
    };
  }
}

class _SortKey {
  _SortKey(this.row, this.n, {this.num, this.text});

  final int row;
  final int n;
  final double? num;
  final _TextKey? text;

  bool get isBlank => num == null && text == null;
}

/// A lower-cased text cut into digit and non-digit runs once, so a sort
/// compares prepared keys instead of cutting both sides at every compare.
class _TextKey implements Comparable<_TextKey> {
  _TextKey(this.raw) {
    for (final m in _runs.allMatches(raw)) {
      final p = m[0]!;
      final isDigit = p.codeUnitAt(0) >= 48 && p.codeUnitAt(0) <= 57;
      parts.add(isDigit ? p.replaceFirst(_zeros, '') : SvEngine._fold(p));
      digits.add(isDigit);
    }
  }

  static final _runs = RegExp(r'\d+|\D+');
  static final _zeros = RegExp(r'^0+(?=\d)');

  final String raw;
  final parts = <String>[];
  final digits = <bool>[];

  @override
  int compareTo(_TextKey other) {
    final n = parts.length < other.parts.length
        ? parts.length
        : other.parts.length;
    for (var i = 0; i < n; i++) {
      final p = parts[i], q = other.parts[i];
      final pd = digits[i], qd = other.digits[i];
      int c;
      if (pd && qd) {
        c = p.length != q.length
            ? p.length.compareTo(q.length)
            : p.compareTo(q);
      } else if (pd != qd) {
        c = pd ? -1 : 1;
      } else {
        c = p.compareTo(q);
      }
      if (c != 0) return c;
    }
    if (parts.length != other.parts.length) {
      return parts.length.compareTo(other.parts.length);
    }
    return raw.compareTo(other.raw);
  }
}
