import 'ids.dart';

List<String> _names(Object? raw) => [
  if (raw is List)
    for (final s in raw)
      if (idText(s).isNotEmpty) idText(s),
];

/// One entry of `record.actions.items`: `send` or `status`.
class RecordActionItem {
  const RecordActionItem({
    required this.id,
    required this.label,
    this.isEnabled = true,
    this.why = '',
  });

  static const send = 'send';
  static const status = 'status';

  final String id;
  final String label;
  final bool isEnabled;

  /// Why it is disabled; shown as it is.
  final String why;

  /// The ids the app knows how to run; any other entry is ignored.
  static const known = {send, status};

  static RecordActionItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = idText(raw['id']);
    if (!known.contains(id)) return null;
    final label = idText(raw['label']);
    return RecordActionItem(
      id: id,
      label: label.isEmpty ? id : label,
      isEnabled: raw['enabled'] != false,
      why: idText(raw['why']),
    );
  }
}

/// A file named in a history reply (`files: {id: {id, name, size, mime}}`).
class RecordFile {
  const RecordFile({
    required this.id,
    required this.name,
    this.size = 0,
    this.mime = '',
  });

  final String id;
  final String name;
  final int size;
  final String mime;

  static RecordFile? tryParse(Object? raw, {String fallbackId = ''}) {
    if (raw is! Map) return null;
    final id = idText(raw['id']).isEmpty ? fallbackId : idText(raw['id']);
    if (id.isEmpty) return null;
    final name = idText(raw['name']);
    return RecordFile(
      id: id,
      name: name.isEmpty ? id : name,
      size: intOf(raw['size']),
      mime: idText(raw['mime']),
    );
  }
}

/// `record.actions {id}`: the menu and the state of one record. The server is
/// the only judge of who may do what: nothing here guesses it.
class RecordState {
  const RecordState({
    required this.items,
    this.holder = '',
    this.claimants = const [],
    this.initiator = '',
    this.assignor = '',
    this.status = '',
    this.statuses = const [],
    this.finalStatuses = const [],
    this.completion,
    this.hours,
    this.isCommentsRequired = false,
    this.isCompletionRequired = false,
    this.isHoursRequired = false,
    this.isFilesRequired = false,
    this.isAdmin = false,
    this.hasRules = false,
    this.lastUpdate,
    this.files = const [],
  });

  final List<RecordActionItem> items;
  final String holder;

  /// Several people it is shared with; empty once someone holds it.
  final List<String> claimants;
  final String initiator;
  final String assignor;
  final String status;
  final List<String> statuses;
  final List<String> finalStatuses;
  final int? completion;

  /// The last hours given, as the server sent them ("2.5").
  final String? hours;
  final bool isCommentsRequired;
  final bool isCompletionRequired;
  final bool isHoursRequired;
  final bool isFilesRequired;
  final bool isAdmin;
  final bool hasRules;
  final Object? lastUpdate;
  final List<String> files;

  /// What a card's bar offers: only what the server returned and enabled.
  /// Nothing is assumed, defaulted or added.
  List<RecordActionItem> get offered => [
    for (final i in items)
      if (i.isEnabled) i,
  ];

  RecordActionItem? item(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  bool get hasSend => item(RecordActionItem.send) != null;
  bool get hasStatus => item(RecordActionItem.status) != null;

  bool get isFinal => finalStatuses.contains(status);

  /// The value `expected` carries: what the screen shows now.
  Map<String, dynamic> get expected => {
    if (status.isNotEmpty) 'status': status,
    if (holder.isNotEmpty) 'holder': holder,
  };

  static RecordState parse(Map<String, dynamic> data) {
    final items = data['items'];
    final completion = data['completion'];
    final hours = data['hours'];
    return RecordState(
      items: [
        if (items is List)
          for (final i in items) ?RecordActionItem.tryParse(i),
      ],
      holder: idText(data['holder']),
      claimants: _names(data['claimants']),
      initiator: idText(data['initiator']),
      assignor: idText(data['assignor']),
      status: idText(data['status']),
      statuses: _names(data['statuses']),
      finalStatuses: _names(data['final']),
      completion: completion == null ? null : intOf(completion).clamp(0, 100),
      hours: hours == null ? null : idText(hours),
      isCommentsRequired: data['commentsRequired'] == true,
      isCompletionRequired: data['completionRequired'] == true,
      isHoursRequired: data['hoursRequired'] == true,
      isFilesRequired: data['filesRequired'] == true,
      isAdmin: data['isAdmin'] == true,
      hasRules: data['hasRules'] == true,
      lastUpdate: data['lastUpdate'],
      files: _names(data['files']),
    );
  }
}

/// What `record.status` and `record.send` answer: a patch, not the record.
class RecordPatch {
  const RecordPatch({
    required this.id,
    this.holder = '',
    this.assignor,
    this.status = '',
    this.completion,
    this.hours,
    this.isFinal = false,
    this.files = const [],
    this.isRepeated = false,
  });

  final int id;
  final String holder;

  /// Only `record.send` carries it.
  final String? assignor;
  final String status;
  final int? completion;
  final String? hours;
  final bool isFinal;
  final List<String> files;

  /// The server answered a retry with the first result (`repeated: true`).
  final bool isRepeated;

  static RecordPatch parse(Map<String, dynamic> data) {
    final completion = data['completion'];
    final hours = data['hours'];
    return RecordPatch(
      id: idNumber(data['id']) ?? 0,
      holder: idText(data['holder']),
      assignor: data.containsKey('assignor') ? idText(data['assignor']) : null,
      status: idText(data['status']),
      completion: completion == null ? null : intOf(completion).clamp(0, 100),
      hours: hours == null ? null : idText(hours),
      isFinal: data['final'] == true,
      files: _names(data['files']),
      isRepeated: data['repeated'] == true,
    );
  }
}

/// One `edited` change: `{field, from, to}`.
class RecordChange {
  const RecordChange({required this.field, this.from = '', this.to = ''});

  final String field;
  final String from;
  final String to;
}

/// One event of `submission.history`, oldest first.
class RecordEvent {
  const RecordEvent({
    required this.id,
    required this.op,
    required this.by,
    required this.ts,
    this.to = const [],
    this.reason = '',
    this.remarks = '',
    this.via = '',
    this.value = '',
    this.fromHolder = '',
    this.isAsAdmin = false,
    this.isClaimed = false,
    this.status = '',
    this.fromStatus = '',
    this.toStatus = '',
    this.completion = '',
    this.hours = '',
    this.isFinal = false,
    this.files = const [],
    this.changes = const [],
  });

  /// Every operation the server names.
  static const ops = [
    'created',
    'edited',
    'deleted',
    'sent_for_approval',
    'waiting',
    'approved',
    'declined',
    'returned',
    'resubmitted',
    'approved_final',
    'sent',
    'status',
    'reassigned',
  ];

  final int id;
  final String op;
  final String by;
  final int ts;
  final List<String> to;
  final String reason;
  final String remarks;
  final String via;
  final String value;
  final String fromHolder;
  final bool isAsAdmin;
  final bool isClaimed;
  final String status;
  final String fromStatus;
  final String toStatus;
  final String completion;
  final String hours;
  final bool isFinal;
  final List<String> files;
  final List<RecordChange> changes;

  static RecordEvent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final op = idText(raw['op']);
    if (op.isEmpty) return null;
    final changes = raw['changes'];
    return RecordEvent(
      id: intOf(raw['id']),
      op: op,
      by: idText(raw['by']),
      ts: intOf(raw['ts']),
      to: _names(raw['to']),
      reason: idText(raw['reason']),
      remarks: idText(raw['remarks']),
      via: idText(raw['via']),
      value: idText(raw['value']),
      fromHolder: idText(raw['fromHolder']),
      isAsAdmin: raw['asAdmin'] == true,
      isClaimed: raw['claimed'] == true,
      status: idText(raw['status']),
      fromStatus: idText(raw['fromStatus']),
      toStatus: idText(raw['toStatus']),
      completion: idText(raw['completion']),
      hours: idText(raw['hours']),
      isFinal: raw['final'] == true,
      files: _names(raw['files']),
      changes: [
        if (changes is List)
          for (final c in changes)
            if (c is Map)
              RecordChange(
                field: idText(c['field']),
                from: idText(c['from']),
                to: idText(c['to']),
              ),
      ],
    );
  }
}

/// `submission.history {id}`.
class RecordHistory {
  const RecordHistory({
    required this.events,
    this.names = const {},
    this.files = const {},
    this.fields = const {},
    this.caption = '',
  });

  /// Oldest first, as the server sends it.
  final List<RecordEvent> events;

  /// username -> display name.
  final Map<String, String> names;
  final Map<String, RecordFile> files;

  /// Field name -> label.
  final Map<String, String> fields;
  final String caption;

  String nameOf(String user) => names[user] ?? user;

  static RecordHistory parse(Map<String, dynamic> data) {
    final events = data['events'];
    final names = data['names'];
    final files = data['files'];
    final fields = data['fields'];
    return RecordHistory(
      events: [
        if (events is List)
          for (final e in events) ?RecordEvent.tryParse(e),
      ],
      names: {
        if (names is Map)
          for (final e in names.entries) idText(e.key): idText(e.value),
      },
      files: {
        if (files is Map)
          for (final e in files.entries)
            idText(e.key): ?RecordFile.tryParse(
              e.value,
              fallbackId: idText(e.key),
            ),
      },
      fields: {
        if (fields is Map)
          for (final e in fields.entries) idText(e.key): idText(e.value),
      },
      caption: idText(data['caption']),
    );
  }
}

/// `record.targets {id}`: what Send may offer for one record now.
class RecordTargets {
  const RecordTargets({
    this.isUnrestricted = false,
    this.designations = const [],
    this.categories = const [],
    this.initiator = '',
    this.assignor = '',
    this.isBlocked = false,
  });

  final bool isUnrestricted;
  final List<String> designations;
  final List<String> categories;

  /// The username to send back to; empty when that is not offered.
  final String initiator;
  final String assignor;
  final bool isBlocked;

  static RecordTargets parse(Map<String, dynamic> data) => RecordTargets(
    isUnrestricted: data['unrestricted'] == true,
    designations: _names(data['designations']),
    categories: _names(data['categories']),
    initiator: idText(data['initiator']),
    assignor: idText(data['assignor']),
    isBlocked: data['blocked'] == true,
  );
}

/// One person of `record.people`.
class RecordPerson {
  const RecordPerson({
    required this.username,
    required this.name,
    this.designation = '',
  });

  final String username;
  final String name;
  final String designation;

  static RecordPerson? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final username = idText(raw['username']);
    if (username.isEmpty) return null;
    final name = idText(raw['name']);
    return RecordPerson(
      username: username,
      name: name.isEmpty ? username : name,
      designation: idText(raw['designation']),
    );
  }

  static List<RecordPerson> parseAll(Map<String, dynamic> data) {
    final rows = data['people'];
    return [
      if (rows is List)
        for (final r in rows) ?RecordPerson.tryParse(r),
    ];
  }
}

/// `record.thread {id}` -> `{conversation, id, title}`.
class RecordThread {
  const RecordThread({required this.conversation, this.title = ''});

  /// `group:rec-<slug>-<id>`.
  final String conversation;
  final String title;

  static RecordThread? tryParse(Map<String, dynamic> data) {
    final c = idText(data['conversation']);
    return c.isEmpty
        ? null
        : RecordThread(conversation: c, title: idText(data['title']));
  }
}
