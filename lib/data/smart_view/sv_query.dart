import 'engine/sv_engine.dart';
import 'engine/sv_values.dart';
import 'models/sv_row.dart';
import 'sv_columns.dart';

/// What the person asked of one view: search text (all fields or one), the
/// filter conditions and one sort. Plain value, compared by content, so a
/// result can be cached by it.
class SmartViewQuery {
  const SmartViewQuery({
    this.search = '',
    this.scope,
    this.conditions = const [],
    this.sortKey,
    this.isAscending = true,
  });

  static const none = SmartViewQuery();

  final String search;

  /// A column key to search in, or null for every visible column.
  final String? scope;
  final List<SvCondition> conditions;
  final String? sortKey;
  final bool isAscending;

  List<SvCondition> get activeConditions => [
    for (final c in conditions)
      if (SvEngine.isActive(c)) c,
  ];

  /// True when the search or a filter narrows the rows (a sort does not).
  bool get isFiltering =>
      search.trim().isNotEmpty || activeConditions.isNotEmpty;

  bool get isSorting => sortKey != null;
  bool get isEmpty => !isFiltering && !isSorting && scope == null;

  SmartViewQuery copyWith({
    String? search,
    String? Function()? scope,
    List<SvCondition>? conditions,
    String? Function()? sortKey,
    bool? isAscending,
  }) => SmartViewQuery(
    search: search ?? this.search,
    scope: scope == null ? this.scope : scope(),
    conditions: conditions ?? this.conditions,
    sortKey: sortKey == null ? this.sortKey : sortKey(),
    isAscending: isAscending ?? this.isAscending,
  );

  @override
  bool operator ==(Object other) =>
      other is SmartViewQuery &&
      other.search == search &&
      other.scope == scope &&
      other.sortKey == sortKey &&
      other.isAscending == isAscending &&
      other.conditions.length == conditions.length &&
      [
        for (var i = 0; i < conditions.length; i++)
          conditions[i] == other.conditions[i],
      ].every((b) => b);

  @override
  int get hashCode => Object.hash(
    search,
    scope,
    sortKey,
    isAscending,
    Object.hashAll(conditions),
  );
}

/// The engine's view of one open structure: the rows as [SmartViewColumns]
/// shows them (so a hidden field is never in it) as an [EngineTable], and the
/// result of a [SmartViewQuery] as the same [SvRow]s, so cards and table
/// always draw the same list. Built once per data version.
class SvEngineInput {
  SvEngineInput._(this.columns, this.rows, this.table);

  final SmartViewColumns columns;
  final List<SvRow> rows;
  final EngineTable table;

  /// The kinds of column the engine is told about, by the field's declared
  /// type (a structure declares its types, so nothing is inferred).
  static EngineType typeOf(SvColType t) => switch (t) {
    SvColType.number => EngineType.number,
    SvColType.date || SvColType.datetime => EngineType.date,
    SvColType.checkbox => EngineType.bool,
    SvColType.file => EngineType.file,
    _ => EngineType.text,
  };

  static bool _isRaw(SvColType t) =>
      t == SvColType.number ||
      t == SvColType.date ||
      t == SvColType.datetime ||
      t == SvColType.checkbox;

  static SvEngineInput of(SmartViewColumns columns, List<SvRow> rows) {
    final cols = columns.columns;
    final engineCols = [
      for (final c in cols) EngineCol(c.key, c.label, typeOf(c.type)),
    ];
    final data = <Map<String, Object?>>[];
    for (final row in rows) {
      final m = <String, Object?>{};
      for (final c in cols) {
        final cell = columns.cellOf(c, row);
        m[c.key] = _isRaw(c.type)
            ? cell.typed
            : (cell.isEmpty ? null : cell.text);
      }
      data.add(m);
    }
    return SvEngineInput._(columns, rows, EngineTable(engineCols, data));
  }

  EngineCol? col(String key) => table.col(key);

  List<int> _positions(SmartViewQuery q, {DateTime? now}) {
    final scoped = q.scope == null ? null : table.col(q.scope!);
    var idx = SvEngine.filter(
      table,
      search: q.search,
      searchIn: scoped == null ? null : [scoped],
      conditions: q.conditions,
      now: now,
    );
    final key = q.sortKey;
    if (key != null && table.col(key) != null) {
      idx = SvEngine.sort(table, idx, key, q.isAscending);
    }
    return idx;
  }

  /// The rows that pass [q], sorted by it. The source rows are not changed.
  List<SvRow> apply(SmartViewQuery q, {DateTime? now}) {
    if (q.isEmpty || (!q.isFiltering && !q.isSorting)) return rows;
    return [for (final i in _positions(q, now: now)) rows[i]];
  }

  /// How many rows pass [conditions] and [search] (the sheet's live count).
  int count({
    String search = '',
    String? scope,
    List<SvCondition> conditions = const [],
    DateTime? now,
  }) => _positions(
    SmartViewQuery(search: search, scope: scope, conditions: conditions),
    now: now,
  ).length;

  /// The distinct filled values of a column (as text, sorted), up to
  /// [limit]; more than that and the editor should be a text box.
  List<String> distinct(String key, {int limit = 60}) {
    final seen = <String>{};
    for (final r in table.rows) {
      final s = SvValues.plain(r[key]).trim();
      if (s.isNotEmpty) seen.add(s);
      if (seen.length > limit) break;
    }
    final list = seen.toList()
      ..sort((a, b) => SvEngine.compareText(a.toLowerCase(), b.toLowerCase()));
    return list;
  }
}
