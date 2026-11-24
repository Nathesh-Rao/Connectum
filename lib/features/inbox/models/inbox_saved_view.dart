import 'dart:convert';

import 'inbox_filter.dart';

/// The limits and words of the Inbox's saved views (`svViews.js`,
/// `sd_inboxview.erl`).
class InboxViewLimits {
  InboxViewLimits._();

  static const maxViews = 20;

  /// The server allows 60; the web trims to 40, so does the phone.
  static const maxName = 40;
  static const defaultName = 'Default View';
}

/// A refusal made on the phone before a call (name rules, the 20 views).
class InboxViewError implements Exception {
  const InboxViewError(this.message);

  final String message;

  @override
  String toString() => 'InboxViewError($message)';
}

/// One saved view as `inbox.views.get` sends it. [setup] keeps every key it
/// came with, also the ones the phone does not model.
class InboxSavedView {
  const InboxSavedView({
    required this.name,
    required this.setup,
    this.savedTs = 0,
  });

  final String name;
  final Map<String, dynamic> setup;
  final int savedTs;

  /// Null when [raw] is not a view (a view of the web never throws).
  static InboxSavedView? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final view = raw['view'];
    if (name is! String || name.isEmpty || view is! Map) return null;
    final ts = raw['savedTs'];
    return InboxSavedView(
      name: name,
      setup: {for (final e in view.entries) '${e.key}': e.value},
      savedTs: ts is num ? ts.toInt() : 0,
    );
  }
}

/// The answer of `inbox.views.get` / `save` / `delete`.
class InboxViewList {
  const InboxViewList({this.views = const [], this.defaultName});

  final List<InboxSavedView> views;
  final String? defaultName;

  /// Null when the answer holds no `views` list at all.
  static InboxViewList? tryParse(Map<String, dynamic> data) {
    final raw = data['views'];
    if (raw is! List) return null;
    final d = data['default'];
    return InboxViewList(
      views: [for (final v in raw) ?InboxSavedView.tryParse(v)],
      defaultName: d is String && d.isNotEmpty ? d : null,
    );
  }

  InboxSavedView? named(String name) {
    for (final v in views) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// Which names a view may have (`cleanName`, `nameTaken`, the 20 views).
class InboxViewRules {
  InboxViewRules._();

  static const empty = 'Give the view a name.';
  static const reserved =
      'That name is taken by the Default View. Choose another.';
  static const taken = 'A view with that name already exists.';
  static const tooMany =
      'At most ${InboxViewLimits.maxViews} views: remove one first.';

  /// One line, trimmed, at most 40 characters; '' when there is nothing.
  static String clean(Object? raw) {
    final one = '${raw ?? ''}'
        .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final runes = one.runes.take(InboxViewLimits.maxName).toList();
    return String.fromCharCodes(runes).trim();
  }

  static bool isDefaultName(String name) =>
      name.toLowerCase() == InboxViewLimits.defaultName.toLowerCase();

  /// Why [raw] cannot be a view's name ('' when it can). A [isNew] name may
  /// not be the Default View's or one that is there; saving over an open view
  /// may. A name that is not there yet needs room among the 20.
  static String problem(
    String raw,
    List<InboxSavedView> views, {
    required bool isNew,
  }) {
    final name = clean(raw);
    if (name.isEmpty) return empty;
    final isThere = views.any((v) => v.name == name);
    if (isNew) {
      if (isDefaultName(name)) return reserved;
      if (views.any((v) => v.name.toLowerCase() == name.toLowerCase())) {
        return taken;
      }
    }
    if (!isThere && views.length >= InboxViewLimits.maxViews) return tooMany;
    return '';
  }
}

/// The setup of the Inbox as one plain map (the web's `setupOf`,
/// `restoreOf`, `setupKey`). The phone models only part of it; the keys it
/// does not model (`kinds`, `lens`, `approvalPick`, `teamMembers`,
/// `dataForms`, a task or broadcast `folder`, the period and hours of
/// `timing`) are passed through from the view that was opened, so editing on
/// the phone never destroys what the web saved.
class InboxSetup {
  InboxSetup._();

  /// The keys the server keeps (`sd_inboxview.erl`).
  static const keys = [
    'folder',
    'lens',
    'kinds',
    'dataForms',
    'approvalPick',
    'scopePick',
    'wheres',
    'teamMembers',
    'blocks',
    'filters',
    'sort',
    'timing',
  ];

  static const _carried = [
    'lens',
    'kinds',
    'dataForms',
    'approvalPick',
    'teamMembers',
  ];

  /// Folders the phone cannot show as a "Search in" entry.
  static const _keptFolders = ['task', 'broadcast'];

  /// What is saved for [filter] and the Me / My Team switch [scope] (`me` or
  /// `team`), over [base] (the opened view's own map, empty for a new one).
  static Map<String, dynamic> compose(
    Map<String, dynamic> base,
    InboxFilter filter,
    String scope,
  ) {
    final isSwitch = filter.wheres.isEmpty;
    final shown = isSwitch && scope == 'team'
        ? filter.copyWith(wheres: const ['team'])
        : filter;
    final mine = shown.toSetup();
    if (mine['folder'] == 'data' &&
        _keptFolders.contains(base['folder'] as Object?)) {
      mine['folder'] = base['folder'];
    }
    if (isSwitch && scope != 'team') {
      final was = _texts(base['scopePick']).toSet();
      mine['scopePick'] = was.length == 1 && was.first == 'me'
          ? ['me']
          : <String>[];
    }
    for (final k in _carried) {
      if (base.containsKey(k)) mine[k] = base[k];
    }
    final baseTiming = base['timing'];
    final timing = mine['timing'] as Map;
    if (baseTiming is Map &&
        '${baseTiming['from'] ?? ''}' == timing['from'] &&
        '${baseTiming['to'] ?? ''}' == timing['to']) {
      mine['timing'] = {
        for (final e in baseTiming.entries) '${e.key}': e.value,
        ...timing,
      };
    }
    return mine;
  }

  /// A saved view read back (`restoreOf`): the filter and the switch. Every
  /// piece is checked; one of Me / My Team is the switch, the rest "Search
  /// in".
  static ({InboxFilter filter, String scope}) restore(
    Object? raw, {
    bool isTeamShown = true,
  }) {
    var filter = InboxFilter.fromSetup(raw);
    var scope = 'me';
    if (filter.wheres.length == 1 &&
        (filter.wheres.first == InboxWhere.me ||
            filter.wheres.first == InboxWhere.team)) {
      if (filter.wheres.first == InboxWhere.team && isTeamShown) scope = 'team';
      filter = filter.copyWith(wheres: const []);
    }
    return (filter: filter, scope: scope);
  }

  /// The plain list of every record: what Create view keeps.
  static Map<String, dynamic> plain() =>
      compose(const {}, InboxFilter.none, 'me');

  /// The setup as text, keys in order: two setups are the same when their
  /// keys are (`setupKey`).
  static String keyOf(Map<String, dynamic> setup) => jsonEncode(_sorted(setup));

  static Object? _sorted(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _sorted(v[k])};
    }
    if (v is List) return [for (final x in v) _sorted(x)];
    return v;
  }

  static List<String> _texts(Object? v) => [
    if (v is List)
      for (final x in v)
        if (x is String && x.isNotEmpty && x.length <= 200) x,
  ];
}
