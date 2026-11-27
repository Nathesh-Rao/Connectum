import 'engine/sv_engine.dart';
import 'sv_columns.dart';
import 'sv_query.dart';
import 'sv_team.dart';

/// The limits the server enforces on a person's views of one source.
class SvViewLimits {
  SvViewLimits._();

  static const maxNamed = 20;
  static const maxName = 40;
  static const maxFilters = 30;
  static const maxGroups = 5;
  static const maxKeys = 300;
  static const defaultId = '__default';
  static const defaultName = 'Default View';
}

/// The screen state a saved view holds: query (search, filters, sort), the
/// group levels and the column layout, in the web's key names (`hidden` and
/// `order` hold column keys; a quiet column turned on is `+key`). Compared by
/// content: a view is "changed" when its state differs from the saved one.
class SvViewState {
  const SvViewState({
    this.query = SmartViewQuery.none,
    this.groupBy = const [],
    this.hidden = const [],
    this.order = const [],
  });

  static const plain = SvViewState();

  final SmartViewQuery query;
  final List<String> groupBy;
  final List<String> hidden;
  final List<String> order;

  SvViewState copyWith({
    SmartViewQuery? query,
    List<String>? groupBy,
    List<String>? hidden,
    List<String>? order,
  }) => SvViewState(
    query: query ?? this.query,
    groupBy: groupBy ?? this.groupBy,
    hidden: hidden ?? this.hidden,
    order: order ?? this.order,
  );

  /// The search scope is a screen choice, never saved, so it never counts.
  SmartViewQuery get _saved => query.copyWith(scope: () => null);

  int get filterCount => query.activeConditions.length;

  @override
  bool operator ==(Object other) =>
      other is SvViewState &&
      other._saved == _saved &&
      _same(other.groupBy, groupBy) &&
      _same(other.hidden, hidden) &&
      _same(other.order, order);

  @override
  int get hashCode => Object.hash(
    _saved,
    Object.hashAll(groupBy),
    Object.hashAll(hidden),
    Object.hashAll(order),
  );

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One saved view as the server keeps it. Keys this app does not know are
/// kept in [extra] and written back untouched, so web-only settings survive.
class SvSavedView {
  const SvSavedView({
    required this.id,
    required this.name,
    this.search = '',
    this.filters = const [],
    this.sortCol,
    this.sortDir,
    this.groupBy = const [],
    this.hidden = const [],
    this.order = const [],
    this.widths = const {},
    this.kpis = true,
    this.charts = true,
    this.extra = const {},
  });

  static const _known = {
    'id',
    'name',
    'search',
    'filters',
    'sort',
    'groupBy',
    'hidden',
    'order',
    'widths',
    'kpis',
    'charts',
  };

  final String id;
  final String name;
  final String search;
  final List<Map<String, Object?>> filters;
  final String? sortCol;
  final String? sortDir;
  final List<String> groupBy;
  final List<String> hidden;
  final List<String> order;
  final Map<String, Object?> widths;
  final bool kpis;
  final bool charts;
  final Map<String, Object?> extra;

  bool get isDefault => id == SvViewLimits.defaultId;

  /// Tolerant: a wrong type in one key gives that key's default; only a
  /// missing id makes the whole entry unusable (null).
  static SvSavedView? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final name = raw['name'];
    final sort = raw['sort'];
    final dir = sort is Map ? sort['dir'] : null;
    final col = sort is Map ? sort['col'] : null;
    final hasSort = col is String && (dir == 'asc' || dir == 'desc');
    final group = raw['groupBy'];
    final w = raw['widths'];
    return SvSavedView(
      id: id,
      name: name is String ? name : '',
      search: raw['search'] is String ? raw['search'] as String : '',
      filters: [
        if (raw['filters'] is List)
          for (final f in raw['filters'] as List)
            if (f is Map) Map<String, Object?>.from(f),
      ],
      sortCol: hasSort ? col : null,
      sortDir: hasSort ? dir as String : null,
      groupBy: group is String
          ? (group.isEmpty ? const [] : [group])
          : _strings(group),
      hidden: _strings(raw['hidden']),
      order: _strings(raw['order']),
      widths: w is Map ? Map<String, Object?>.from(w) : const {},
      kpis: raw['kpis'] != false,
      charts: raw['charts'] != false,
      extra: {
        for (final e in raw.entries)
          if (e.key is String && !_known.contains(e.key))
            e.key as String: e.value,
      },
    );
  }

  static List<String> _strings(Object? v) => [
    if (v is List)
      for (final s in v)
        if (s is String) s,
  ];

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'name': name,
    'search': search,
    'filters': filters,
    'sort': sortCol == null ? null : {'col': sortCol, 'dir': sortDir},
    'groupBy': groupBy,
    'hidden': hidden,
    'order': order,
    'widths': widths,
    'kpis': kpis,
    'charts': charts,
  };

  SvSavedView copyWith({String? id, String? name}) => SvSavedView(
    id: id ?? this.id,
    name: name ?? this.name,
    search: search,
    filters: filters,
    sortCol: sortCol,
    sortDir: sortDir,
    groupBy: groupBy,
    hidden: hidden,
    order: order,
    widths: widths,
    kpis: kpis,
    charts: charts,
    extra: extra,
  );

  /// The screen state this view stands for over the columns [known]. Filters,
  /// sort and groups naming a column that is not there (a field the form
  /// keeps hidden, or one that is gone) are dropped, link conditions
  /// (`preset: true`) too; the "My team" and "Linked as" lines are not
  /// columns and always stay; nothing outside [known] ever reaches the screen.
  SvViewState toState(Set<String> known) {
    final conditions = <SvCondition>[];
    for (final f in filters) {
      final col = f['col'];
      final op = f['op'];
      if (f['preset'] == true || col is! String || op is! String) continue;
      if (SvTeamCols.isReserved(col)) {
        final line = SvTeam.tryLine(col, op, f['value']);
        if (line != null) conditions.add(line);
        continue;
      }
      final key = SvKeys.mobile(col);
      if (!known.contains(key)) continue;
      conditions.add(SvCondition(key, op, f['value']));
    }
    final sortKey = sortCol == null ? null : SvKeys.mobile(sortCol!);
    final hasSort = sortKey != null && known.contains(sortKey);
    return SvViewState(
      query: SmartViewQuery(
        search: search,
        conditions: conditions,
        sortKey: hasSort ? sortKey : null,
        isAscending: sortDir != 'desc',
      ),
      groupBy: [
        for (final g in groupBy)
          if (known.contains(SvKeys.mobile(g))) g,
      ],
      hidden: hidden,
      order: order,
    );
  }

  /// This view with [s] captured over it: id, name, widths, `kpis`, `charts`
  /// and every unknown key stay; only the parts a screen can change move.
  /// Only active conditions are kept (the web's `captureView`).
  SvSavedView withState(SvViewState s) {
    final q = s.query;
    final key = q.sortKey;
    return SvSavedView(
      id: id,
      name: name,
      search: q.search.trim(),
      filters: [
        for (final c in q.activeConditions)
          {'col': SvKeys.web(c.col), 'op': c.op, 'value': c.value},
      ],
      sortCol: key == null ? null : SvKeys.web(key),
      sortDir: key == null ? null : (q.isAscending ? 'asc' : 'desc'),
      groupBy: [for (final g in s.groupBy) SvKeys.web(g)],
      hidden: s.hidden,
      order: s.order,
      widths: widths,
      kpis: kpis,
      charts: charts,
      extra: extra,
    );
  }

  /// A new view (own id) from [s]: nothing inherited.
  static SvSavedView fresh(String id, String name, SvViewState s) =>
      SvSavedView(id: id, name: name).withState(s);

  /// The same content, compared as JSON: the "was it changed elsewhere"
  /// test.
  bool sameAs(SvSavedView? o) => o != null && _deep(toJson(), o.toJson());

  static bool _deep(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final e in a.entries) {
        if (!b.containsKey(e.key) || !_deep(e.value, b[e.key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deep(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is num && b is num) return a == b;
    return a == b;
  }

  static String cleanName(String raw) {
    final s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.length > SvViewLimits.maxName
        ? s.substring(0, SvViewLimits.maxName).trim()
        : s;
  }
}

/// Column keys: the app's meta columns (`#by`, `#submitted`, `#status`) are
/// the web's `By`, `On`, `Status`; a structure's own fields are the same.
class SvKeys {
  SvKeys._();

  static const _pairs = {
    SmartViewColumns.byKey: 'By',
    SmartViewColumns.submittedKey: 'On',
    SmartViewColumns.statusKey: 'Status',
  };

  static String web(String key) => _pairs[key] ?? key;

  static String mobile(String key) {
    for (final e in _pairs.entries) {
      if (e.value == key) return e.key;
    }
    return key;
  }
}
