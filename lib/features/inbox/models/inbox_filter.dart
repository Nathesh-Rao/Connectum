import 'inbox_query.dart';

/// The entries of "Search in" (`SEARCH_IN`, `WHERES` in the web's
/// `InboxFilterFab.jsx` / `inboxQuery.js`). The model holds every one; the
/// panel offers [offered] (Reminders are out of scope).
class InboxWhere {
  InboxWhere._();

  static const all = 'all';
  static const me = 'me';
  static const team = 'team';
  static const requests = 'requests';
  static const allApprovals = 'allapprovals';
  static const approvals = 'approvals';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const completed = 'completed';
  static const reminders = 'reminders';
  static const escalations = 'escalations';
  static const timeline = 'timeline';

  /// Every entry there is, in the web's order (`WHERES`).
  static const known = [
    me,
    team,
    requests,
    allApprovals,
    approvals,
    approved,
    rejected,
    completed,
    reminders,
    escalations,
    timeline,
  ];

  /// What the panel offers now.
  static const offered = [
    me,
    team,
    requests,
    allApprovals,
    approvals,
    approved,
    rejected,
    completed,
    escalations,
    timeline,
  ];

  /// The entries read from the approval list, not from records (`APPROVAL_STAGE`):
  /// the answer each holds (`any` is every request).
  static const stageOf = {
    allApprovals: 'any',
    approvals: 'pending',
    approved: 'approved',
    rejected: 'rejected',
  };

  static const labels = {
    all: 'All records',
    me: 'Me',
    team: 'My Team',
    requests: 'Requests',
    allApprovals: 'Approvals',
    approvals: 'Pending my approvals',
    approved: 'Approved',
    rejected: 'Rejected',
    completed: 'Completed',
    reminders: 'Reminders',
    escalations: 'Escalations',
    timeline: 'Timeline',
  };

  /// The entries that are lines of `records.query` (`VIEW_OF`).
  static const _viewOf = {me, team, requests, completed, escalations, timeline};

  /// The folder of the web's saved view for an entry (`WHERE_FOLDER`).
  static const folderOf = {
    requests: 'requests',
    allApprovals: 'allapprovals',
    approvals: 'approval',
    approved: 'approved',
    rejected: 'rejected',
    completed: 'completed',
    reminders: 'reminder',
    escalations: 'escalation',
  };

  /// The choice after a change (`whereChoice`): only known entries, each
  /// once; Timeline alone when it was just chosen, never with the others.
  /// [before] is the choice until now.
  static List<String> choice(List<String> before, List<String> next) {
    final list = <String>{
      for (final w in next)
        if (known.contains(w)) w,
    }.toList();
    final rest = [
      for (final w in list)
        if (w != timeline) w,
    ];
    if (list.contains(timeline) &&
        (!before.contains(timeline) || rest.isEmpty)) {
      return const [timeline];
    }
    return rest;
  }
}

/// The server's limits (`inboxQuery.js`).
class InboxFilterLimits {
  InboxFilterLimits._();

  static const maxBlocks = 10;
  static const maxConditions = 20;
  static const escalationDays = 3;
  static const maxNames = 50;
  static const maxNameChars = 200;
}

/// Operators by field kind (`OPERATORS`): `[id the server knows, words]`.
class InboxOps {
  InboxOps._();

  static const text = [
    ('contains', 'contains'),
    ('eq', 'is'),
    ('ne', 'is not'),
    ('starts', 'starts with'),
    ('ends', 'ends with'),
    ('empty', 'is empty'),
    ('notempty', 'is not empty'),
  ];
  static const number = [
    ('eq', '='),
    ('ne', '≠'),
    ('gt', '>'),
    ('gte', '≥'),
    ('lt', '<'),
    ('lte', '≤'),
    ('between', 'between'),
    ('empty', 'is empty'),
    ('notempty', 'is not empty'),
  ];
  static const date = [
    ('eq', 'is'),
    ('lt', 'before'),
    ('gt', 'after'),
    ('lte', 'on or before'),
    ('gte', 'on or after'),
    ('between', 'between'),
    ('empty', 'is empty'),
    ('notempty', 'is not empty'),
  ];
  static const bools = [('eq', 'is')];

  /// How a field of this column type is filtered (`kindOfType`): number,
  /// date, bool, else text.
  static String kindOfType(String? type) =>
      type == 'number' || type == 'date' || type == 'bool' ? type! : 'text';

  /// The operators of a field kind (text when the kind is not known).
  static List<(String, String)> of(String kind) => switch (kind) {
    'number' => number,
    'date' => date,
    'bool' => bools,
    _ => text,
  };

  /// Does this operator need a value (empty and not empty do not)?
  static bool needsValue(String op) => op != 'empty' && op != 'notempty';
}

int _idCounter = 0;
String _nextId() => 'q${++_idCounter}';

/// One condition of a block: a field, an operator, a value (two for between).
class InboxCondition {
  InboxCondition({
    String? id,
    this.field = '',
    this.op = '',
    this.value = '',
    this.value2 = '',
    this.join = 'and',
  }) : id = id ?? _nextId();

  /// A condition with only its field chosen; the operator starts as the
  /// field kind's first (`newCondition`).
  factory InboxCondition.forField(String field, [String kind = 'text']) =>
      InboxCondition(field: field, op: InboxOps.of(kind).first.$1);

  final String id;
  final String field;
  final String op;
  final String value;
  final String value2;

  /// `and` or `or`, read from the left.
  final String join;

  InboxCondition copyWith({
    String? field,
    String? op,
    String? value,
    String? value2,
    String? join,
  }) => InboxCondition(
    id: id,
    field: field ?? this.field,
    op: op ?? this.op,
    value: value ?? this.value,
    value2: value2 ?? this.value2,
    join: join ?? this.join,
  );

  /// A condition the server can run: a field, an operator, and a value when
  /// the operator needs one (two for between) (`conditionReady`).
  bool get isReady {
    if (field.isEmpty || op.isEmpty) return false;
    if (!InboxOps.needsValue(op)) return true;
    return value.trim().isNotEmpty &&
        (op != 'between' || value2.trim().isNotEmpty);
  }

  Map<String, dynamic> toArgs() => {
    'field': field,
    'op': op,
    'join': join == 'or' ? 'or' : 'and',
    if (InboxOps.needsValue(op)) ...{
      'value': value.trim(),
      if (op == 'between') 'value2': value2.trim(),
    },
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'field': field,
    'op': op,
    'value': value,
    'value2': value2,
    'join': join == 'or' ? 'or' : 'and',
  };
}

List<String> _texts(Object? v) => [
  if (v is List)
    for (final x in v)
      if (x is String &&
          x.isNotEmpty &&
          x.length <= InboxFilterLimits.maxNameChars)
        x,
];

String _text(Object? v) =>
    v is String && v.length <= InboxFilterLimits.maxNameChars ? v : '';

/// The names a line may hold: strings of 1-200 characters, at most 50
/// (`names`).
List<String> inboxNames(Object? v) =>
    _texts(v).take(InboxFilterLimits.maxNames).toList();

/// One block of the Advanced filter: forms, who made the records, who sent
/// them, to whom, and conditions on fields.
class InboxBlock {
  InboxBlock({
    String? id,
    this.forms = const [],
    this.createdBy = const [],
    this.sentBy = const [],
    this.sentTo = const [],
    this.conditions = const [],
  }) : id = id ?? _nextId();

  final String id;
  final List<String> forms;
  final List<String> createdBy;
  final List<String> sentBy;
  final List<String> sentTo;
  final List<InboxCondition> conditions;

  InboxBlock copyWith({
    List<String>? forms,
    List<String>? createdBy,
    List<String>? sentBy,
    List<String>? sentTo,
    List<InboxCondition>? conditions,
  }) => InboxBlock(
    id: id,
    forms: forms ?? this.forms,
    createdBy: createdBy ?? this.createdBy,
    sentBy: sentBy ?? this.sentBy,
    sentTo: sentTo ?? this.sentTo,
    conditions: conditions ?? this.conditions,
  );

  /// Does the block say anything (a form, a person, a ready condition)? A
  /// block that says nothing is dropped (`blockActive`).
  bool get isActive =>
      forms.isNotEmpty ||
      createdBy.isNotEmpty ||
      sentBy.isNotEmpty ||
      sentTo.isNotEmpty ||
      conditions.any((c) => c.isReady);

  /// The conditions the server can run: only when ONE form is named (a field
  /// belongs to a form), the ready ones, at most 20 (`readyConditions`).
  List<Map<String, dynamic>> get readyConditions => forms.length == 1
      ? [
          for (final c
              in conditions
                  .where((c) => c.isReady)
                  .take(InboxFilterLimits.maxConditions))
            c.toArgs(),
        ]
      : const [];

  /// A group for each form named (the same people and, for one form, the
  /// same conditions), or one group for every form (`groupsOfBlock`).
  List<Map<String, dynamic>> get groups {
    final people = {
      if (createdBy.isNotEmpty) 'createdBy': createdBy,
      if (sentBy.isNotEmpty) 'sentBy': sentBy,
      if (sentTo.isNotEmpty) 'sentTo': sentTo,
    };
    final conds = readyConditions;
    return forms.isNotEmpty
        ? [
            for (final f in forms) {'form': f, ...people, 'conditions': conds},
          ]
        : [
            {...people, 'conditions': conds},
          ];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'forms': forms,
    'createdBy': createdBy,
    'sentBy': sentBy,
    'sentTo': sentTo,
    'conditions': [for (final c in conditions) c.toJson()],
  };

  /// Blocks read back from anywhere untrusted (`reviveBlocks`): only what a
  /// block holds, each piece checked, a new id when it has none; anything
  /// that is not a block is dropped, at most 10.
  static List<InboxBlock> revive(Object? list) {
    String id(Object? v) =>
        v is String && RegExp(r'^[\w-]{1,40}$').hasMatch(v) ? v : _nextId();
    return [
      if (list is List)
        for (final b in list.whereType<Map<dynamic, dynamic>>().take(
          InboxFilterLimits.maxBlocks,
        ))
          InboxBlock(
            id: id(b['id']),
            forms: b['forms'] != null
                ? _texts(b['forms'])
                : _text(b['form']).isNotEmpty
                ? [_text(b['form'])]
                : const [],
            createdBy: _texts(b['createdBy']),
            sentBy: _texts(b['sentBy']),
            sentTo: _texts(b['sentTo']),
            conditions: [
              if (b['conditions'] is List)
                for (final c
                    in (b['conditions'] as List)
                        .whereType<Map<dynamic, dynamic>>()
                        .take(InboxFilterLimits.maxConditions))
                  InboxCondition(
                    id: id(c['id']),
                    field: _text(c['field']),
                    op: _text(c['op']),
                    value: _text(c['value']),
                    value2: _text(c['value2']),
                    join: c['join'] == 'or' ? 'or' : 'and',
                  ),
            ],
          ),
    ];
  }
}

/// The answers of an approval flow Advanced > Approval ticks.
class InboxApprovalAnswer {
  InboxApprovalAnswer._();

  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const all = [pending, approved, rejected];
  static const labels = {
    pending: 'Pending',
    approved: 'Approved',
    rejected: 'Rejected',
  };
}

/// The four orders of Sort (client side only, `SORTS`) and the two statuses
/// the server cuts to.
class InboxSort {
  InboxSort._();

  static const latest = 'latest';
  static const oldest = 'oldest';
  static const asc = 'asc';
  static const desc = 'desc';
  static const open = 'open';
  static const closed = 'closed';

  static const orders = [latest, oldest, asc, desc];

  /// What the Sort line offers, in the web's order and words.
  static const choices = [
    (latest, 'Latest'),
    (oldest, 'Oldest'),
    (asc, 'Ascending (A to Z)'),
    (desc, 'Descending (Z to A)'),
    (open, 'Open only'),
    (closed, 'Closed only'),
  ];
}

final _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// The people lines of the panel, in the order the panel shows them.
const inboxPeopleKeys = ['createdBy', 'sentBy', 'sentTo', 'taggedTo'];

/// The Inbox filter as the person builds it (the panel's draft) and as it is
/// applied: a port of the web's `inboxQuery.js` and of the panel's own state
/// (`InboxFilterFab.jsx`). Immutable; a change returns a new filter.
///
/// [wheres] is the "Search in" choice (empty is All records). [status] is the
/// `open` / `closed` of the Sort line; [sort] is one of the four orders.
/// [blocks] are the Advanced blocks. The model can later be kept as a saved
/// view with [toSetup] / [InboxFilter.fromSetup] (the web's keys).
class InboxFilter {
  const InboxFilter({
    this.wheres = const [],
    this.forms = const [],
    this.createdBy = const [],
    this.sentBy = const [],
    this.sentTo = const [],
    this.taggedTo = const [],
    this.from = '',
    this.to = '',
    this.sort = InboxSort.latest,
    this.status = '',
    this.blocks = const [],
    this.approvalPick = const [],
  });

  static const none = InboxFilter();

  final List<String> wheres;
  final List<String> forms;
  final List<String> createdBy;
  final List<String> sentBy;
  final List<String> sentTo;
  final List<String> taggedTo;

  /// `YYYY-MM-DD` or ''.
  final String from;
  final String to;

  /// One of [InboxSort.orders].
  final String sort;

  /// `open`, `closed` or ''.
  final String status;
  final List<InboxBlock> blocks;

  /// Advanced > Approval: the answers ticked (`pending`, `approved`,
  /// `rejected`); a client side cut of the approval list. None is off.
  final List<String> approvalPick;

  InboxFilter copyWith({
    List<String>? wheres,
    List<String>? forms,
    List<String>? createdBy,
    List<String>? sentBy,
    List<String>? sentTo,
    List<String>? taggedTo,
    String? from,
    String? to,
    String? sort,
    String? status,
    List<InboxBlock>? blocks,
    List<String>? approvalPick,
  }) => InboxFilter(
    wheres: wheres ?? this.wheres,
    forms: forms ?? this.forms,
    createdBy: createdBy ?? this.createdBy,
    sentBy: sentBy ?? this.sentBy,
    sentTo: sentTo ?? this.sentTo,
    taggedTo: taggedTo ?? this.taggedTo,
    from: from ?? this.from,
    to: to ?? this.to,
    sort: sort ?? this.sort,
    status: status ?? this.status,
    blocks: blocks ?? this.blocks,
    approvalPick: approvalPick ?? this.approvalPick,
  );

  /// One of a people line by its key (`createdBy`, `sentBy`, `sentTo`,
  /// `taggedTo`).
  List<String> peopleOf(String key) => switch (key) {
    'createdBy' => createdBy,
    'sentBy' => sentBy,
    'sentTo' => sentTo,
    'taggedTo' => taggedTo,
    _ => const [],
  };

  InboxFilter withPeople(String key, List<String> names) => switch (key) {
    'createdBy' => copyWith(createdBy: names),
    'sentBy' => copyWith(sentBy: names),
    'sentTo' => copyWith(sentTo: names),
    'taggedTo' => copyWith(taggedTo: names),
    _ => this,
  };

  /// What the Sort line shows: the status when one is chosen, else the order.
  String get sortChoice => status.isNotEmpty ? status : sort;

  /// A choice of the Sort line (`InboxFilterFab.jsx:125`): Open only / Closed
  /// only set the status (the order goes back to latest); an order clears it.
  InboxFilter withSortChoice(String choice) =>
      choice == InboxSort.open || choice == InboxSort.closed
      ? copyWith(sort: InboxSort.latest, status: choice)
      : copyWith(
          sort: InboxSort.orders.contains(choice) ? choice : InboxSort.latest,
          status: '',
        );

  /// Is any day chosen?
  bool get hasDays => from.isNotEmpty || to.isNotEmpty;

  /// How many of the panel's lines say something: the badge (`filterCount`).
  /// [baseWhere] is the entry the list shows anyway (the Me / My Team
  /// switch); a choice of only that entry says nothing.
  int filterCount({String? baseWhere}) {
    final isBase =
        baseWhere != null && wheres.length == 1 && wheres.first == baseWhere;
    return (wheres.isNotEmpty && !isBase ? 1 : 0) +
        (forms.isNotEmpty ? 1 : 0) +
        (createdBy.isNotEmpty ? 1 : 0) +
        (sentBy.isNotEmpty ? 1 : 0) +
        (sentTo.isNotEmpty ? 1 : 0) +
        (taggedTo.isNotEmpty ? 1 : 0) +
        (hasDays ? 1 : 0) +
        (status.isNotEmpty ? 1 : 0) +
        (sort != InboxSort.latest ? 1 : 0) +
        blocks.where((b) => b.isActive).length +
        (approvalPick.isNotEmpty ? 1 : 0);
  }

  /// Does anything narrow the list (other than the Me / My Team switch)?
  bool isActive({String? baseWhere}) => filterCount(baseWhere: baseWhere) > 0;

  /// Do the lines other than the order say anything (what the server runs)?
  bool get isServerFilter =>
      wheres.isNotEmpty ||
      forms.isNotEmpty ||
      createdBy.isNotEmpty ||
      sentBy.isNotEmpty ||
      sentTo.isNotEmpty ||
      taggedTo.isNotEmpty ||
      hasDays ||
      status.isNotEmpty ||
      blocks.any((b) => b.isActive);

  /// The `views` of `records.query` for the choice (`serverViews`): one per
  /// entry the server reads, none when the choice is only approvals and
  /// reminders. No choice (or All) is one empty view, which is not sent.
  /// [team] is the person's reports (`records.people`), for Requests.
  List<Map<String, dynamic>> serverViews([List<String> team = const []]) {
    final picks = wheres.isEmpty ? const [InboxWhere.all] : wheres;
    if (picks.contains(InboxWhere.all)) return const [{}];
    return [
      for (final w in picks)
        if (InboxWhere._viewOf.contains(w)) _viewOf(w, team),
    ];
  }

  Map<String, dynamic> _viewOf(String w, List<String> team) => switch (w) {
    InboxWhere.me => {
      'scope': ['me'],
    },
    InboxWhere.team => {
      'scope': ['team'],
    },
    // Raised by the person and their team, unless Created by already says who.
    InboxWhere.requests =>
      inboxNames(createdBy).isNotEmpty
          ? <String, dynamic>{}
          : {
              'createdBy': ['me', ...inboxNames(team).take(49)],
            },
    InboxWhere.completed => {'status': 'closed'},
    InboxWhere.escalations => {
      'escalated': {'days': InboxFilterLimits.escalationDays},
    },
    _ => <String, dynamic>{},
  };

  /// The groups to send: only the blocks that say something, at most 10
  /// groups (`groupsOf`).
  List<Map<String, dynamic>> get groups => [
    for (final b in blocks.where((b) => b.isActive)) ...b.groups,
  ].take(InboxFilterLimits.maxBlocks).toList();

  /// The ask of the list. [scope] is the Me / My Team switch (`me` / `team`),
  /// sent only when "Search in" holds no entry of its own. [team] are the
  /// reports' names.
  InboxQuery toQuery({String? scope, List<String> team = const []}) {
    final views = serverViews(team);
    return InboxQuery(
      scope: wheres.isEmpty && scope != null ? [scope] : const [],
      forms: inboxNames(forms),
      createdBy: inboxNames(createdBy),
      sentBy: inboxNames(sentBy),
      sentTo: inboxNames(sentTo),
      taggedTo: inboxNames(taggedTo),
      from: _day.hasMatch(from) ? from : '',
      to: _day.hasMatch(to) ? to : '',
      status: status == 'open' || status == 'closed' ? status : '',
      views: wheres.isEmpty ? const [] : views,
      groups: groups,
    );
  }

  /// The ask for the panel's lists (`facetArgs`): the panel as it stands,
  /// the forms ticked included (the people lists follow them; the server
  /// leaves them out of the form counts), never the blocks. `limit:1`,
  /// `offset:0`.
  InboxQuery toFacetQuery({List<String> team = const []}) => InboxQuery(
    forms: inboxNames(forms),
    createdBy: inboxNames(createdBy),
    sentBy: inboxNames(sentBy),
    sentTo: inboxNames(sentTo),
    taggedTo: inboxNames(taggedTo),
    from: _day.hasMatch(from) ? from : '',
    to: _day.hasMatch(to) ? to : '',
    status: status == 'open' || status == 'closed' ? status : '',
    views: wheres.isEmpty ? const [] : serverViews(team),
    isFacets: true,
  );

  /// Which lines the facets ask depends on: the facets answer for one group
  /// of "Search in" at a time (`wheres.join(",")`).
  String get group => wheres.join(',');

  /// The filter in the web's saved-view keys (`setupOf`): `folder`,
  /// `scopePick` (one of me / team), `wheres` (two or more), `dataForms`,
  /// `filters`, `sort`, `timing`, `blocks`, and the keys the phone does not
  /// model, empty (`lens`, `kinds`, `teamMembers`), so the
  /// shape is the web's whole `setupOf`. `InboxSetup.compose` puts the keys
  /// of an opened view back over them.
  Map<String, dynamic> toSetup() {
    final one = wheres.length == 1 ? wheres.first : '';
    return {
      'folder': InboxWhere.folderOf[one] ?? 'data',
      'lens': '',
      'kinds': <String>[],
      'approvalPick': approvalPick,
      'teamMembers': <String>[],
      'scopePick': one == InboxWhere.me || one == InboxWhere.team
          ? [one]
          : <String>[],
      'wheres': wheres.length > 1 ? wheres : <String>[],
      'dataForms': <String>[],
      'filters': {
        'forms': forms,
        'createdBy': createdBy,
        'sentBy': sentBy,
        'sentTo': sentTo,
        'taggedTo': taggedTo,
        'status': status,
      },
      'sort': sort,
      'timing': {'from': from, 'to': to},
      'blocks': [for (final b in blocks) b.toJson()],
    };
  }

  /// A filter read back from a saved view (or anywhere untrusted): every
  /// piece checked, anything else is "none".
  factory InboxFilter.fromSetup(Object? raw) {
    if (raw is! Map) return none;
    final f = raw['filters'] is Map ? raw['filters'] as Map : const {};
    final timing = raw['timing'] is Map ? raw['timing'] as Map : const {};
    final scope = _texts(
      raw['scopePick'],
    ).where((x) => x == 'me' || x == 'team').toSet();
    final several = _texts(raw['wheres'])
        .where((x) => InboxWhere.known.contains(x) && x != InboxWhere.timeline)
        .toSet();
    final folder = InboxWhere.folderOf.entries
        .where((e) => e.value == raw['folder'])
        .map((e) => e.key)
        .firstOrNull;
    String day(Object? v) => v is String && _day.hasMatch(v) ? v : '';
    return InboxFilter(
      wheres: several.length > 1
          ? several.toList()
          : scope.length == 1
          ? scope.toList()
          : folder != null
          ? [folder]
          : const [],
      forms: inboxNames(f['forms']),
      createdBy: inboxNames(f['createdBy']),
      sentBy: inboxNames(f['sentBy']),
      sentTo: inboxNames(f['sentTo']),
      taggedTo: inboxNames(f['taggedTo']),
      from: day(timing['from']),
      to: day(timing['to']),
      sort: InboxSort.orders.contains(raw['sort'])
          ? raw['sort'] as String
          : InboxSort.latest,
      status: f['status'] == 'open' || f['status'] == 'closed'
          ? f['status'] as String
          : '',
      blocks: InboxBlock.revive(raw['blocks']),
      approvalPick: [
        for (final a in _texts(raw['approvalPick']).toSet())
          if (InboxApprovalAnswer.all.contains(a)) a,
      ],
    );
  }
}

/// The people a person list offers (`peopleChoices`): "Me" first, then the
/// usernames given, each once. With [isListed] the names are exactly who is
/// on the records ("Me" only when `me` is among them).
List<({String id, String label})> inboxPeopleChoices(
  List<String> usernames,
  String Function(String) nameOf, {
  bool isListed = false,
}) {
  return [
    if (!isListed || usernames.contains('me')) (id: 'me', label: 'Me'),
    for (final u in <String>{...usernames})
      if (u.isNotEmpty && u != 'me') (id: u, label: nameOf(u)),
  ];
}
