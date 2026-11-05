import 'ids.dart';

List<String> _strings(Object? raw) => [
  if (raw is List)
    for (final s in raw)
      if (idText(s).isNotEmpty) idText(s),
];

/// One status of a form's table.
class TicketStatus {
  const TicketStatus(this.name, {this.isFinal = false});

  final String name;
  final bool isFinal;
}

/// One thing a person can do to a ticket, as the form defines it. All words
/// are data: nothing looks at a name.
class TicketAction {
  const TicketAction({
    required this.name,
    this.who = const [],
    this.from = const [],
    this.to = '',
    this.assign = 'keep',
    this.percent = 'none',
    this.reason = 'none',
    this.remarks = 'none',
    this.attachments = 'none',
    this.reasons = const [],
    this.push = false,
  });

  final String name;

  /// admin | assignee | raiser | pool.
  final List<String> who;

  /// Empty = any status that is not final.
  final List<String> from;
  final String to;

  /// pick | keep | raiser | previous | self.
  final String assign;

  /// none | set | hundred.
  final String percent;

  /// none | optional | required.
  final String reason;
  final String remarks;
  final String attachments;
  final List<String> reasons;
  final bool push;

  bool get asksReason => reason == 'optional' || reason == 'required';
  bool get asksRemarks => remarks == 'optional' || remarks == 'required';
  bool get asksSendTo => assign == 'pick';
  bool get asksPercent => percent == 'set';
  bool get asksFiles => attachments == 'optional' || attachments == 'required';

  static TicketAction? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = idText(raw['name']);
    if (name.isEmpty) return null;
    String word(String key, String fallback) {
      final v = idText(raw[key]);
      return v.isEmpty ? fallback : v;
    }

    final attachments = raw['attachments'];
    return TicketAction(
      name: name,
      who: _strings(raw['who']),
      from: _strings(raw['from']),
      to: idText(raw['to']),
      assign: word('assign', 'keep'),
      percent: word('percent', 'none'),
      reason: word('reason', 'none'),
      remarks: word('remarks', 'none'),
      attachments: attachments is Map
          ? idText(attachments['mode'])
          : word('attachments', 'none'),
      reasons: _strings(raw['reasons']),
      push: raw['push'] == true,
    );
  }
}

/// `structures[form].status`: where a ticket stands and what can be done.
class TicketTable {
  const TicketTable({
    required this.field,
    this.assignee,
    this.completion,
    this.subject,
    this.pool,
    this.statuses = const [],
    this.editableIn = const [],
    this.actions = const [],
  });

  final String field;
  final String? assignee;
  final String? completion;

  /// The field a ticket is titled by; null when the form has none.
  final String? subject;

  /// The field naming the group a ticket waits for.
  final String? pool;
  final List<TicketStatus> statuses;
  final List<String> editableIn;
  final List<TicketAction> actions;

  /// The status a new record starts at.
  String get firstStatus => statuses.isEmpty ? '' : statuses.first.name;

  bool isFinal(String status) {
    for (final s in statuses) {
      if (s.name == status) return s.isFinal;
    }
    return false;
  }

  /// Fields shown in the header, not as record values.
  Set<String> get headerFields => {field, ?assignee, ?completion, ?subject};

  static TicketTable? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final field = idText(raw['field']);
    if (field.isEmpty) return null;
    String? optional(String key) {
      final v = idText(raw[key]);
      return v.isEmpty ? null : v;
    }

    final statuses = raw['statuses'];
    final actions = raw['actions'];
    return TicketTable(
      field: field,
      assignee: optional('assignee'),
      completion: optional('completion'),
      subject: optional('subject'),
      pool: optional('pool'),
      statuses: [
        if (statuses is List)
          for (final s in statuses)
            if (s is Map && idText(s['name']).isNotEmpty)
              TicketStatus(idText(s['name']), isFinal: s['final'] == true)
            else if (s is String && s.isNotEmpty)
              TicketStatus(s),
      ],
      editableIn: _strings(raw['editableIn']),
      actions: [
        if (actions is List)
          for (final a in actions) ?TicketAction.tryParse(a),
      ],
    );
  }
}

/// `structures[form]`.
class TicketForm {
  const TicketForm({
    required this.key,
    required this.caption,
    this.fields = const {},
    this.hasThread = false,
    this.table,
  });

  final String key;
  final String caption;

  /// Field name -> label.
  final Map<String, String> fields;
  final bool hasThread;
  final TicketTable? table;

  String labelOf(String name) => fields[name] ?? name;

  static TicketForm? tryParse(String key, Object? raw) {
    if (raw is! Map) return null;
    final fields = raw['fields'];
    final caption = idText(raw['caption']);
    return TicketForm(
      key: key,
      caption: caption.isEmpty ? key : caption,
      fields: {
        if (fields is Map)
          for (final e in fields.entries) idText(e.key): idText(e.value),
      },
      hasThread: raw['recordThread'] == true,
      table: TicketTable.tryParse(raw['status']),
    );
  }

  static Map<String, TicketForm> parseAll(Object? raw) {
    final forms = <String, TicketForm>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final form = TicketForm.tryParse(idText(e.key), e.value);
        if (form != null) forms[form.key] = form;
      }
    }
    return forms;
  }
}

/// One ticket: the record and, when the reply carried it, its form.
class Ticket {
  const Ticket({
    required this.id,
    required this.by,
    required this.ts,
    required this.tstruct,
    this.values = const {},
    this.branch = '',
    this.host,
    this.scope = '',
    this.recordStatus = '',
    this.form,
  });

  final int id;
  final String by;
  final int ts;
  final String tstruct;
  final Map<String, dynamic> values;
  final String branch;
  final String? host;
  final String scope;

  /// The record's own `status` (`pending` while it waits for approval).
  final String recordStatus;
  final TicketForm? form;

  TicketTable? get table => form?.table;

  /// The reply named a status table for this form: it is a ticket.
  bool get isTicket => table != null;

  String get caption => form?.caption ?? tstruct;

  /// Saved, but not a record yet: it waits for someone to approve it.
  bool get isAwaitingApproval {
    if (recordStatus.toLowerCase() == 'pending') return true;
    final t = table;
    if (t == null) return false;
    final raw = idText(values[t.field]).trim().toLowerCase();
    return raw == 'pending' &&
        !t.statuses.any((s) => s.name.toLowerCase() == raw);
  }

  String get ref => '$caption #$id';

  /// The subject, or `<caption> #<id>` when empty.
  String get title {
    final field = table?.subject;
    if (field != null) {
      final text = idText(values[field]).trim();
      if (text.isNotEmpty) return text;
    }
    return ref;
  }

  /// The status; the first of the table when the record has none.
  String get status {
    final t = table;
    if (t == null) return '';
    final text = idText(values[t.field]).trim();
    return text.isEmpty ? t.firstStatus : text;
  }

  bool get isFinal => table?.isFinal(status) ?? false;

  /// Who it is with (a username); the person who raised it when no one is
  /// named.
  String get withWhom {
    final field = table?.assignee;
    if (field != null) {
      final text = idText(values[field]).trim();
      if (text.isNotEmpty) return text;
    }
    return by;
  }

  /// 0 to 100.
  int get completion {
    final field = table?.completion;
    if (field == null) return 0;
    return intOf(values[field]).clamp(0, 100);
  }

  /// A group is named for the ticket to wait for.
  bool get hasPool {
    final field = table?.pool;
    if (field == null) return false;
    final v = values[field];
    if (v is List) return v.isNotEmpty;
    return idText(v).trim().isNotEmpty;
  }

  bool isRaisedBy(String user) => by.toLowerCase() == user.toLowerCase();
  bool isWith(String user) => withWhom.toLowerCase() == user.toLowerCase();

  /// The ticket after an update answered with its new state.
  Ticket applying(TicketUpdateResult r) {
    final t = table;
    if (t == null) return this;
    return copyWith(
      values: {
        ...values,
        t.field: r.status,
        if (t.assignee != null) t.assignee!: r.assignee,
        if (t.completion != null) t.completion!: r.completion,
      },
      recordStatus: '',
    );
  }

  Ticket copyWith({
    Map<String, dynamic>? values,
    String? recordStatus,
    TicketForm? form,
  }) => Ticket(
    id: id,
    by: by,
    ts: ts,
    tstruct: tstruct,
    values: values ?? this.values,
    branch: branch,
    host: host,
    scope: scope,
    recordStatus: recordStatus ?? this.recordStatus,
    form: form ?? this.form,
  );

  static Ticket? tryParse(Object? raw, Map<String, TicketForm> forms) {
    if (raw is! Map) return null;
    final id = idNumber(raw['id']);
    if (id == null) return null;
    final tstruct = idText(raw['tstruct']);
    final values = raw['values'];
    return Ticket(
      id: id,
      by: idText(raw['by']),
      ts: intOf(raw['ts']),
      tstruct: tstruct,
      values: values is Map
          ? {for (final e in values.entries) idText(e.key): e.value}
          : const {},
      branch: idText(raw['branch']),
      host: raw['host'] == null ? null : idText(raw['host']),
      scope: idText(raw['scope']),
      recordStatus: idText(raw['status']),
      form: forms[tstruct],
    );
  }
}

/// A `status.mine` reply.
class TicketPage {
  const TicketPage({
    required this.tickets,
    required this.forms,
    required this.total,
    required this.hasMore,
  });

  final List<Ticket> tickets;
  final Map<String, TicketForm> forms;
  final int total;
  final bool hasMore;

  static TicketPage parse(Map<String, dynamic> data) {
    final forms = TicketForm.parseAll(data['structures']);
    final rows = data['submissions'];
    final tickets = [
      if (rows is List)
        for (final r in rows) ?Ticket.tryParse(r, forms),
    ];
    return TicketPage(
      tickets: tickets,
      forms: forms,
      total: data['total'] == null ? tickets.length : intOf(data['total']),
      hasMore: data['hasMore'] == true,
    );
  }
}

/// A `status.get` reply.
class TicketDetail {
  const TicketDetail({
    required this.ticket,
    required this.isAdmin,
    this.inPool,
  });

  final Ticket ticket;
  final bool isAdmin;

  /// Whether this person is in the group the ticket waits for; null when the
  /// server did not say.
  final bool? inPool;

  static TicketDetail? tryParse(Map<String, dynamic> data) {
    final forms = TicketForm.parseAll(data['structures']);
    final ticket = Ticket.tryParse(data['submission'], forms);
    if (ticket == null) return null;
    return TicketDetail(
      ticket: ticket,
      isAdmin: data['isAdmin'] == true,
      inPool: data['inPool'] is bool ? data['inPool'] as bool : null,
    );
  }
}

/// A file of a history record.
class TicketFile {
  const TicketFile({required this.id, required this.name});

  final String id;
  final String name;
}

/// One step of `status.history`.
class TicketHistoryEntry {
  const TicketHistoryEntry({
    required this.id,
    required this.by,
    required this.ts,
    required this.action,
    this.isByAdmin = false,
    this.fromStatus = '',
    this.toStatus = '',
    this.remarks = '',
    this.reason = '',
    this.percent = '',
    this.sentTo = '',
    this.files = const [],
  });

  final int id;
  final String by;
  final int ts;
  final String action;
  final bool isByAdmin;
  final String fromStatus;
  final String toStatus;
  final String remarks;
  final String reason;
  final String percent;
  final String sentTo;
  final List<TicketFile> files;

  static TicketHistoryEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final v = raw['values'] is Map ? raw['values'] as Map : const {};
    String text(String key) => idText(v[key]).trim();
    final files = <TicketFile>[];
    final rawFiles = raw['files'] ?? v['Files'] ?? v['files'];
    if (rawFiles is List) {
      for (final f in rawFiles) {
        if (f is Map) {
          final id = idText(f['id']);
          final name = idText(f['name']);
          if (id.isNotEmpty || name.isNotEmpty) {
            files.add(TicketFile(id: id, name: name.isEmpty ? id : name));
          }
        } else if (idText(f).isNotEmpty) {
          files.add(TicketFile(id: idText(f), name: idText(f)));
        }
      }
    }
    return TicketHistoryEntry(
      id: intOf(raw['id']),
      by: idText(raw['by']),
      ts: intOf(raw['ts']),
      action: text('Action'),
      isByAdmin: text('ByAdmin').toLowerCase() == 'yes',
      fromStatus: text('FromStatus'),
      toStatus: text('ToStatus'),
      remarks: text('Remarks'),
      reason: text('Reason'),
      percent: text('Percent'),
      sentTo: text('SentTo'),
      files: files,
    );
  }

  /// Oldest first, as the server sends it.
  static List<TicketHistoryEntry> parseAll(Map<String, dynamic> data) {
    final rows = data['history'];
    return [
      if (rows is List)
        for (final r in rows) ?TicketHistoryEntry.tryParse(r),
    ];
  }
}

/// The ok answer of `status.update`.
class TicketUpdateResult {
  const TicketUpdateResult({
    required this.status,
    required this.assignee,
    required this.completion,
    this.record,
    this.ticket,
    this.isRepeated = false,
  });

  final String status;
  final String assignee;
  final int completion;
  final int? record;
  final int? ticket;

  /// The server answered a retry with the first result.
  final bool isRepeated;

  static TicketUpdateResult parse(Map<String, dynamic> data) =>
      TicketUpdateResult(
        status: idText(data['status']),
        assignee: idText(data['assignee']),
        completion: intOf(data['completion']).clamp(0, 100),
        record: idNumber(data['record']),
        ticket: idNumber(data['ticket']),
        isRepeated: data['repeated'] == true,
      );
}

/// The live event `ticket_assigned {id, tstruct, action, by}`.
class TicketAssigned {
  const TicketAssigned({
    required this.id,
    this.tstruct = '',
    this.action = '',
    this.by = '',
  });

  final int id;
  final String tstruct;
  final String action;
  final String by;

  bool get isRaised => action == 'Raised';

  static TicketAssigned? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = idNumber(raw['id']);
    if (id == null) return null;
    return TicketAssigned(
      id: id,
      tstruct: idText(raw['tstruct']),
      action: idText(raw['action']),
      by: idText(raw['by']),
    );
  }
}
