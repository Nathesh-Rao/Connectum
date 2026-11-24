import '../../../data/models/ids.dart';
import 'inbox_row.dart';

/// One answer of `records.query`: a page of rows.
class InboxPage {
  const InboxPage({
    required this.rows,
    required this.forms,
    required this.total,
    required this.hasMore,
    required this.isCapped,
    this.received = 0,
  });

  final List<InboxRow> rows;
  final Map<String, InboxForm> forms;

  /// Exact over what the server looks at (it reads each list to 1,000).
  final int total;
  final bool hasMore;

  /// A list was longer than the server reads.
  final bool isCapped;

  /// Rows in the reply, readable or not; paging goes on from
  /// `offset + received`.
  final int received;

  static const empty = InboxPage(
    rows: [],
    forms: {},
    total: 0,
    hasMore: false,
    isCapped: false,
  );

  /// The same row shape as `records.mine` (`workItems.js` uses one parser).
  static InboxPage parse(Map<String, dynamic> data) {
    final forms = InboxForm.parseAll(data['structures']);
    final raw = data['submissions'];
    final rows = [
      if (raw is List)
        for (final r in raw) ?InboxRow.tryParse(r, forms),
    ];
    final total = intOf(data['total']);
    return InboxPage(
      rows: rows,
      forms: forms,
      total: total > 0 ? total : rows.length,
      hasMore: data['hasMore'] == true,
      isCapped: data['capped'] == true,
      received: raw is List ? raw.length : 0,
    );
  }

  /// This page followed by [next]; a record already listed is not listed
  /// twice (the web's `appendWork`).
  InboxPage append(InboxPage next) {
    final seen = {for (final r in rows) r.id};
    return InboxPage(
      rows: [
        ...rows,
        for (final r in next.rows)
          if (seen.add(r.id)) r,
      ],
      forms: {...forms, ...next.forms},
      total: next.total,
      hasMore: next.hasMore,
      isCapped: isCapped || next.isCapped,
      received: received + next.received,
    );
  }
}

/// `records.counts`: how many records each view holds.
class InboxCounts {
  const InboxCounts({
    required this.me,
    required this.team,
    required this.all,
    this.reports = 0,
    this.cap = 1000,
  });

  final int me;
  final int team;
  final int all;

  /// How many reports the person has (the Team view shows when > 0).
  final int reports;

  /// Counts are exact up to the cap; more is `cap + 1`.
  final int cap;

  bool isOverCap(int n) => n > cap;

  /// "12", or "1000+" over the cap.
  String label(int n) => isOverCap(n) ? '$cap+' : '$n';

  /// Null unless me, team and all are numbers (the web's rule).
  static InboxCounts? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final me = raw['me'];
    final team = raw['team'];
    final all = raw['all'];
    if (me is! num || team is! num || all is! num) return null;
    final reports = intOf(raw['reports']);
    final cap = intOf(raw['cap']);
    return InboxCounts(
      me: me.toInt(),
      team: team.toInt(),
      all: all.toInt(),
      reports: reports,
      cap: cap > 0 ? cap : 1000,
    );
  }
}

/// `records.people`: the user names the filter's people lists offer.
class InboxPeople {
  const InboxPeople({
    this.team = const [],
    this.sentBy = const [],
    this.sentTo = const [],
  });

  final List<String> team;
  final List<String> sentBy;
  final List<String> sentTo;

  static List<String> _names(Object? v) => [
    if (v is List)
      for (final u in v)
        if (u is String) u,
  ];

  static InboxPeople parse(Map<String, dynamic> data) => InboxPeople(
    team: _names(data['team']),
    sentBy: _names(data['sentBy']),
    sentTo: _names(data['sentTo']),
  );
}

/// What the filter panel's lists offer, from a `records.query` asked with
/// `facets:true` (`loadFacets`): how many records each form has under the
/// other lines, and who is on those records for each people line.
class InboxFacets {
  const InboxFacets({this.forms = const {}, this.people = const {}});

  /// Form -> records (only forms with at least one).
  final Map<String, int> forms;

  /// `createdBy`, `sentBy`, `sentTo`, `taggedTo` -> user names (the caller is
  /// `me`).
  final Map<String, List<String>> people;

  List<String> peopleOf(String key) => people[key] ?? const [];

  static InboxFacets parse(Map<String, dynamic> data) {
    final raw = data['formCounts'];
    final who = data['people'];
    List<String> names(String key) => [
      if (who is Map && who[key] is List)
        for (final u in who[key] as List)
          if (u is String && u.isNotEmpty) u,
    ];
    return InboxFacets(
      forms: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String &&
                (e.key as String).isNotEmpty &&
                e.value is num &&
                (e.value as num) > 0)
              e.key as String: (e.value as num).toInt(),
      },
      people: {
        for (final k in const ['createdBy', 'sentBy', 'sentTo', 'taggedTo'])
          k: names(k),
      },
    );
  }
}

/// One person of `people.cards`.
class PersonCard {
  const PersonCard({
    required this.username,
    this.name = '',
    this.designation = '',
    this.role = '',
    this.avatar = '',
  });

  final String username;
  final String name;
  final String designation;
  final String role;
  final String avatar;

  static PersonCard? tryParse(String username, Object? raw) {
    if (username.isEmpty || raw is! Map) return null;
    return PersonCard(
      username: username,
      name: idText(raw['name']),
      designation: idText(raw['designation']),
      role: idText(raw['role']),
      avatar: idText(raw['avatar']),
    );
  }
}
