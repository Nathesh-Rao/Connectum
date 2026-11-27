import 'engine/sv_engine.dart';

/// One way a team member can be tied to a record: the id the server knows,
/// the words of the panel and what it means.
class SvLinkedWay {
  const SvLinkedWay(this.id, this.label, this.hint);

  final String id;
  final String label;
  final String hint;
}

/// What the server is asked for the team lines (`records.query` `team`).
class SvTeamFilter {
  const SvTeamFilter({this.members = const [], this.linked = const []});

  final List<String> members;
  final List<String> linked;

  bool get isEmpty => members.isEmpty && linked.isEmpty;

  /// `{members, linked}` with only what is set (`team: {}` is never sent).
  Map<String, dynamic> toArgs() => {
    if (members.isNotEmpty) 'members': members,
    if (linked.isNotEmpty) 'linked': linked,
  };

  @override
  bool operator ==(Object other) =>
      other is SvTeamFilter &&
      _same(other.members, members) &&
      _same(other.linked, linked);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(members), Object.hashAll(linked));

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The "My team" and "Linked as" lines of the filter panel, as the web's
/// `svFilters.js` keeps them: two reserved conditions in the list of
/// conditions, never columns.
class SvTeam {
  SvTeam._();

  static const maxMembers = 50;

  static const ways = [
    SvLinkedWay(
      'tagged',
      'Tagged to',
      'Named in a field of people on the record.',
    ),
    SvLinkedWay(
      'assignedTo',
      'Assigned to',
      'Holds the record now and did not make it.',
    ),
    SvLinkedWay(
      'assignedBy',
      'Assigned by',
      'Sent the record on (assigning is sending).',
    ),
    SvLinkedWay('sentTo', 'Sent to', 'The record was sent or shared to them.'),
    SvLinkedWay('sentBy', 'Sent by', 'Sent the record on.'),
    SvLinkedWay('raisedBy', 'Raised by', 'Made the record.'),
    SvLinkedWay(
      'raisedTo',
      'Raised to',
      'Has it now, or is named in it, and did not make it.',
    ),
    SvLinkedWay(
      'pending',
      'Pending with team',
      'Has it now and it is still open.',
    ),
    SvLinkedWay('requests', 'Requests', 'Made the record.'),
  ];

  static final _wayIds = {for (final w in ways) w.id};

  static String wayLabel(String id) {
    for (final w in ways) {
      if (w.id == id) return w.label;
    }
    return id;
  }

  /// True for the two reserved conditions, whatever their value.
  static bool isTeamLine(SvCondition c) => SvTeamCols.isReserved(c.col);

  /// A reserved condition as a saved view or a link may hold it: `in` with a
  /// list; texts only. Anything else is not a team line.
  static SvCondition? tryLine(String col, String op, Object? value) {
    if (!SvTeamCols.isReserved(col) || op != 'in' || value is! List) {
      return null;
    }
    final list = <String>{
      for (final v in value)
        if (v is String && v.isNotEmpty) v,
    }.toList();
    return SvCondition(col, 'in', list);
  }

  static List<String> _listOf(List<SvCondition> conditions, String col) {
    for (final c in conditions) {
      if (c.col == col && c.op == 'in' && c.value is List) {
        return <String>{
          for (final v in c.value as List)
            if (v is String && v.isNotEmpty) v,
        }.toList();
      }
    }
    return const [];
  }

  /// What to ask the server for [conditions]; null when neither line is set.
  static SvTeamFilter? of(List<SvCondition> conditions) {
    final members = _listOf(conditions, SvTeamCols.team);
    final linked = [
      for (final id in _listOf(conditions, SvTeamCols.linked))
        if (_wayIds.contains(id)) id,
    ];
    if (members.isEmpty && linked.isEmpty) return null;
    return SvTeamFilter(
      members: members.take(maxMembers).toList(),
      linked: linked,
    );
  }

  /// The members and ways set in [conditions] (as chosen, unfiltered).
  static List<String> membersOf(List<SvCondition> conditions) =>
      _listOf(conditions, SvTeamCols.team);

  static List<String> waysOf(List<SvCondition> conditions) =>
      _listOf(conditions, SvTeamCols.linked);

  /// [conditions] without the two lines.
  static List<SvCondition> without(List<SvCondition> conditions) => [
    for (final c in conditions)
      if (!isTeamLine(c)) c,
  ];

  /// The conditions with the two lines set to [members] and [linked]
  /// (a line with no choice goes); every other condition stays.
  static List<SvCondition> withLines(
    List<SvCondition> conditions,
    List<String> members,
    List<String> linked,
  ) => [
    ...without(conditions),
    if (members.isNotEmpty) SvCondition(SvTeamCols.team, 'in', members),
    if (linked.isNotEmpty) SvCondition(SvTeamCols.linked, 'in', linked),
  ];

  /// "My team: Ravi, Sana +1" / "Linked as: Tagged to, Pending with team";
  /// [nameOf] shows a user name (the user name itself until it is known).
  static String chipText(SvCondition c, String Function(String) nameOf) {
    final isLinked = c.col == SvTeamCols.linked;
    final raw = [
      if (c.value is List)
        for (final v in c.value as List)
          if (v is String) v,
    ];
    final words = [for (final v in raw) isLinked ? wayLabel(v) : nameOf(v)];
    final shown = words.take(2).join(', ');
    final more = words.length > 2 ? ' +${words.length - 2}' : '';
    return '${isLinked ? 'Linked as' : 'My team'}: $shown$more';
  }
}
