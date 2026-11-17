import 'ids.dart';
import 'record_state.dart';

List<String> _strings(Object? raw) => [
  if (raw is List)
    for (final s in raw)
      if (idText(s).isNotEmpty) idText(s),
];

String _plain(Object? v) {
  if (v is List) return v.map(_plain).where((x) => x.isNotEmpty).join(', ');
  if (v is Map || v is bool) return '';
  return idText(v).trim();
}

/// One status of a form's table.
class TicketStatus {
  const TicketStatus(this.name, {this.isFinal = false});

  final String name;
  final bool isFinal;
}

/// `structures[form].status`: only the field and the statuses. The first
/// status is where a record starts; any status can move to any other.
class TicketTable {
  const TicketTable({required this.field, this.statuses = const []});

  final String field;
  final List<TicketStatus> statuses;

  /// The status a new record starts at.
  String get firstStatus => statuses.isEmpty ? '' : statuses.first.name;

  bool isFinal(String status) {
    for (final s in statuses) {
      if (s.name == status) return s.isFinal;
    }
    return false;
  }

  /// Fields shown in the header, not as record values: the status and the four
  /// hidden fields the server keeps beside it.
  Set<String> get headerFields => {
    field,
    '${field}_completion',
    '${field}_comments',
    '${field}_files',
    '${field}_hours',
  };

  static TicketTable? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final field = idText(raw['field']);
    if (field.isEmpty) return null;
    final statuses = _strings(raw['statuses']);
    final finals = _strings(raw['final']).toSet();
    return TicketTable(
      field: field,
      statuses: [
        for (final s in statuses) TicketStatus(s, isFinal: finals.contains(s)),
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

/// One record with a status: the submission and, when the reply carried it,
/// its form. `holder`, `assignor` and `completion` come with the submission
/// in `records.mine`; `record.actions` is the full, current state.
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
    this.holder = '',
    this.assignor = '',
    this.completion = 0,
    this.participants = const [],
    this.editedTs = 0,
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

  /// Who it is with now; empty until the server says.
  final String holder;
  final String assignor;

  /// 0 to 100.
  final int completion;
  final List<String> participants;
  final int editedTs;
  final TicketForm? form;

  TicketTable? get table => form?.table;

  /// The form has a status field.
  bool get hasStatus => table != null;

  String get caption => form?.caption ?? tstruct;

  /// Saved, but not a record yet: it waits for someone to approve it.
  bool get isAwaitingApproval => recordStatus.toLowerCase() == 'pending';

  String get ref => '$caption #$id';

  /// The first filled value of the form, or `<caption> #<id>` when empty.
  String get title {
    final t = table;
    final order = form?.fields.keys ?? values.keys;
    for (final key in order) {
      if (t != null && t.headerFields.contains(key)) continue;
      final text = _plain(values[key]);
      if (text.isNotEmpty && text.length <= 80) return text;
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
  String get withWhom => holder.isNotEmpty ? holder : by;

  bool isRaisedBy(String user) => by.toLowerCase() == user.toLowerCase();
  bool isWith(String user) => withWhom.toLowerCase() == user.toLowerCase();

  /// The ticket after `record.status` / `record.send` answered with a patch.
  Ticket applying(RecordPatch r) {
    final t = table;
    return Ticket(
      id: id,
      by: by,
      ts: ts,
      tstruct: tstruct,
      values: {
        ...values,
        if (t != null && r.status.isNotEmpty) t.field: r.status,
      },
      branch: branch,
      host: host,
      scope: scope,
      recordStatus: '',
      holder: r.holder.isEmpty ? holder : r.holder,
      assignor: r.assignor ?? assignor,
      completion: r.completion ?? completion,
      participants: participants,
      editedTs: editedTs,
      form: form,
    );
  }

  Ticket copyWith({
    Map<String, dynamic>? values,
    String? recordStatus,
    String? holder,
    String? assignor,
    int? completion,
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
    holder: holder ?? this.holder,
    assignor: assignor ?? this.assignor,
    completion: completion ?? this.completion,
    participants: participants,
    editedTs: editedTs,
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
      holder: idText(raw['holder']),
      assignor: idText(raw['assignor']),
      completion: intOf(raw['completion']).clamp(0, 100),
      participants: _strings(raw['participants']),
      editedTs: intOf(raw['editedTs']),
      form: forms[tstruct],
    );
  }
}

/// A `records.mine` reply.
class TicketPage {
  const TicketPage({
    required this.tickets,
    required this.forms,
    required this.total,
    required this.hasMore,
    this.received = 0,
    this.next,
  });

  final List<Ticket> tickets;

  /// How many rows the reply held, readable or not: paging continues from
  /// `offset + received` (`next` is null for `with` and `involved`).
  final int received;

  /// The position the server says to continue from. Real for `raised` and
  /// `team`; always null for `with` and `involved`.
  final int? next;

  /// Where the next page of list [as] starts, given the offset of this one:
  /// `offset + received` for `with` and `involved` (the web does the same),
  /// the server's `next` for `raised` (it scans more rows than it returns).
  int nextOffset(String as, int offset) =>
      (as == 'raised' || as == 'team') && next != null
      ? next!
      : offset + received;
  final Map<String, TicketForm> forms;

  /// Real for `with` and `involved`; for `raised` the server only counts the
  /// rows of this page, so the screen never shows it there.
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
      received: rows is List ? rows.length : 0,
      next: data['next'] == null ? null : intOf(data['next']),
    );
  }
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
