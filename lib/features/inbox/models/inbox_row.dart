import '../../../data/models/ids.dart';
import 'inbox_record_tone.dart';

/// `structures[form]` of a `records.query` / `records.mine` reply: only what
/// the Inbox reads. Unlike `TicketForm` it keeps the status's `final` list as
/// the server sent it (the web checks the record's status against that list).
class InboxForm {
  const InboxForm({
    required this.key,
    required this.caption,
    this.fields = const {},
    this.statusField = '',
    this.finals = const [],
  });

  final String key;
  final String caption;

  /// Field name -> caption.
  final Map<String, String> fields;
  final String statusField;
  final List<String> finals;

  static InboxForm? tryParse(String key, Object? raw) {
    if (raw is! Map) return null;
    final fields = raw['fields'];
    final status = raw['status'];
    final caption = idText(raw['caption']);
    return InboxForm(
      key: key,
      caption: caption.isEmpty ? key : caption,
      fields: {
        if (fields is Map)
          for (final e in fields.entries) idText(e.key): idText(e.value),
      },
      statusField: status is Map ? idText(status['field']) : '',
      finals: [
        if (status is Map && status['final'] is List)
          for (final s in status['final'] as List) idText(s),
      ],
    );
  }

  static Map<String, InboxForm> parseAll(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        idText(e.key): ?InboxForm.tryParse(idText(e.key), e.value),
  };
}

const _titleField = r'^(title|name|subject|summary|what|heading)$';
final _titleRe = RegExp(_titleField, caseSensitive: false);

/// The values a status and a send keep beside their field: not a record's
/// name (`svStatus.js` `keptParts`).
Set<String> keptParts(String statusField) => {
  if (statusField.isNotEmpty)
    for (final c in const ['comments', 'completion', 'files', 'hours'])
      '${statusField}_$c',
  for (final p in const ['to', 'reason', 'remarks', 'files']) 'send_$p',
};

/// One record of the Inbox, with what a card needs. Port of the web's
/// `workItem` (`workItems.js`): the same rows come from `records.query` and
/// `records.mine`. Unlike `Ticket` it keeps `claimants`, `labels`,
/// `team.{via,members,links}`, `actedBy` and `externalId`, which the web needs.
class InboxRow {
  const InboxRow({
    required this.id,
    required this.formId,
    required this.form,
    required this.subject,
    required this.holder,
    required this.raiser,
    required this.ts,
    this.fields = const {},
    this.values = const {},
    this.labels = const {},
    this.files = const {},
    this.statusField = '',
    this.state = '',
    this.pct,
    this.recordStatus = '',
    this.isWaiting = false,
    this.isFinal = false,
    this.via = const [],
    this.members = const [],
    this.links,
    this.actedBy = '',
    this.externalId = '',
  });

  final int id;
  final String formId;

  /// The form's caption.
  final String form;
  final Map<String, String> fields;
  final Map<String, dynamic> values;
  final Map<String, dynamic> labels;

  /// `files[field]`: the details of the file ids a field holds (`withDetails`
  /// and `fileMeta:2`); empty when the server did not send them.
  final Map<String, dynamic> files;
  final String statusField;
  final String subject;

  /// Lower case; "a, @b" when shared with several people.
  final String holder;
  final String raiser;

  /// The record's own status text ('' when the form has none).
  final String state;
  final int? pct;

  /// The record's approval answer (`pending`, `approved`, `rejected`).
  final String recordStatus;

  /// The form's approval step has not answered yet.
  final bool isWaiting;

  /// At a status that ends the record.
  final bool isFinal;
  final int ts;
  final List<String> via;
  final List<String> members;
  final Map<String, dynamic>? links;
  final String actedBy;
  final String externalId;

  /// The status chip's colour family: 'done' at a final status, else 'live'.
  String get tone => isFinal ? 'done' : 'live';

  /// The answer of the approval flow for a record with no status of its own.
  String get approvalAnswer => recordStatus == 'approved'
      ? 'Approved'
      : recordStatus == 'rejected'
      ? 'Rejected'
      : '';

  /// What the chip says when the record's live status is not known
  /// (`HashInboxModal.jsx` `workRow`): "Waiting for approval" while the
  /// approval step is open, else the status, else the approval answer.
  String get badge => isWaiting
      ? 'Waiting for approval'
      : state.isNotEmpty
      ? state
      : approvalAnswer;

  /// The chip text: the record's live status (from `record.actions`) when it
  /// has one, else [badge]; '' means no chip.
  String chipText(String? liveStatus) {
    final live = (liveStatus ?? '').trim();
    return live.isNotEmpty ? live : badge;
  }

  /// The person the card is about: who it is with (the first, when shared),
  /// else who raised it.
  String get who {
    final text = holder.isNotEmpty ? holder : raiser;
    return text.split(',').first.replaceFirst('@', '').trim();
  }

  /// "You" when the card is about [me].
  bool isAbout(String me) => me.isNotEmpty && who == me.toLowerCase();

  /// The name under the person's face: "You", else [cardName], else the user
  /// name.
  String whoLabel(String me, {String? cardName}) {
    if (isAbout(me)) return 'You';
    final name = (cardName ?? '').trim();
    return name.isNotEmpty ? name : who;
  }

  /// Does [q] (lower case, not empty) occur in what the card shows below its
  /// header: a field's caption, an answer (its readable label too) or the
  /// name of a file? The status field is left out, as on the card.
  bool hasAnswerText(String q) {
    bool has(Object? v) => v is String && v.toLowerCase().contains(q);
    bool deep(Object? v) =>
        v is List ? v.any(deep) : has(v) || (v is num && '$v'.contains(q));
    for (final e in values.entries) {
      if (e.key == statusField) continue;
      if (has(fields[e.key] ?? e.key) || deep(e.value) || deep(labels[e.key])) {
        return true;
      }
    }
    for (final info in files.values) {
      if (info is! List) continue;
      for (final f in info) {
        if (f is Map && has(f['name'])) return true;
      }
    }
    return false;
  }

  InboxPriority? get priority =>
      priorityOf(values: values, labels: labels, fields: fields);

  /// The state colour for the person [me] (`cardState` in `WorkCards.jsx`).
  InboxState stateFor(String me, {String view = ''}) => recordStateOf(
    isFinal: isFinal || (recordStatus == 'approved' && state.isEmpty),
    isWaiting: isWaiting,
    isDeclined: recordStatus == 'rejected',
    statusText: state,
    holder: holder,
    via: via,
    me: me,
    view: view,
  );

  static String _subject(
    Map<String, dynamic> values,
    InboxForm? form,
    String caption,
    int id,
  ) {
    final skip = keptParts(form?.statusField ?? '');
    if (form != null && form.statusField.isNotEmpty) skip.add(form.statusField);
    bool short(MapEntry<String, dynamic> e) =>
        !skip.contains(e.key) &&
        e.value is String &&
        (e.value as String).trim().isNotEmpty &&
        (e.value as String).length <= 120;
    MapEntry<String, dynamic>? found;
    for (final e in values.entries) {
      if (_titleRe.hasMatch(e.key) && short(e)) {
        found = e;
        break;
      }
    }
    if (found == null) {
      for (final e in values.entries) {
        if (short(e)) {
          found = e;
          break;
        }
      }
    }
    return found != null ? (found.value as String).trim() : '$caption #$id';
  }

  static Map<String, dynamic> _map(Object? raw) => raw is Map
      ? {for (final e in raw.entries) idText(e.key): e.value}
      : const {};

  /// One record, or null when it is not one (no numeric id).
  static InboxRow? tryParse(Object? raw, Map<String, InboxForm> forms) {
    if (raw is! Map) return null;
    final id = idNumber(raw['id']);
    if (id == null) return null;
    final tstruct = idText(raw['tstruct']);
    final form = forms[tstruct];
    final caption = form?.caption ?? tstruct;
    final values = _map(raw['values']);
    final statusValue = form != null && form.statusField.isNotEmpty
        ? values[form.statusField]
        : null;
    final state = statusValue is String ? statusValue : '';
    final completion = raw['completion'];
    final claimants = raw['claimants'];
    final by = idText(raw['by']);
    final holder = claimants is List && claimants.isNotEmpty
        ? [for (final u in claimants) idText(u).toLowerCase()].join(', @')
        : (idText(raw['holder']).isNotEmpty ? idText(raw['holder']) : by)
              .toLowerCase();
    final team = raw['team'];
    final via = team is Map && team['via'] is List
        ? [for (final v in team['via'] as List) idText(v)]
        : const <String>[];
    final members = team is Map && team['members'] is List
        ? [for (final m in team['members'] as List) idText(m).toLowerCase()]
        : const <String>[];
    final links = team is Map && team['links'] is Map
        ? _map(team['links'])
        : null;
    return InboxRow(
      id: id,
      formId: tstruct,
      form: caption,
      fields: form?.fields ?? const {},
      values: values,
      labels: _map(raw['labels']),
      files: _map(raw['files']),
      statusField: form?.statusField ?? '',
      subject: _subject(values, form, caption, id),
      holder: holder,
      raiser: by.toLowerCase(),
      state: state,
      pct: completion is int
          ? completion
          : completion is double && completion == completion.truncateToDouble()
          ? completion.toInt()
          : null,
      recordStatus: idText(raw['status']),
      isWaiting: raw['status'] == 'pending',
      isFinal: form != null && form.finals.contains(state),
      ts: intOf(raw['ts']),
      via: via,
      members: members,
      links: links,
      actedBy: idText(raw['actedBy']).toLowerCase(),
      externalId: idText(raw['externalId']),
    );
  }
}
