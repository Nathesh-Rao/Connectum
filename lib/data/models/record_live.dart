import 'ids.dart';
import 'record_state.dart';
import 'ticket.dart';

/// The `record` object of an event, a form card or `records.summary`:
/// `{status, holder, claimants, completion, final, ts, by}`. `status` and
/// `completion` are null for a form without a status.
class RecordSummary {
  const RecordSummary({
    this.status = '',
    this.holder = '',
    this.claimants = const [],
    this.completion,
    this.isFinal = false,
    this.ts = 0,
    this.by = '',
  });

  final String status;
  final String holder;
  final List<String> claimants;
  final int? completion;
  final bool isFinal;

  /// Milliseconds of the record's last change; orders late events.
  final int ts;
  final String by;

  /// Null when [raw] is not a `record` object: the record is then unknown, not
  /// without a status.
  static RecordSummary? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final claimants = raw['claimants'];
    final completion = raw['completion'];
    return RecordSummary(
      status: idText(raw['status']),
      holder: idText(raw['holder']),
      claimants: [
        if (claimants is List)
          for (final c in claimants)
            if (idText(c).isNotEmpty) idText(c),
      ],
      completion: completion == null ? null : intOf(completion).clamp(0, 100),
      isFinal: raw['final'] == true,
      ts: intOf(raw['ts']),
      by: idText(raw['by']),
    );
  }
}

/// What a record card shows about its record: the status, who it is with,
/// how far it is and the last update. It is filled from data that is already
/// at hand (a `record.actions` read, a `records.mine` page, the answer of my
/// own action, an event) and never from a read made for the card. A record
/// event says only that something changed ([isStale]), so what is shown stays
/// until the menu or the record is opened and reads `record.actions` again.
class RecordLive {
  const RecordLive({
    this.status = '',
    this.holder = '',
    this.initiator = '',
    this.claimants = const [],
    this.completion,
    this.lastBy = '',
    this.lastTs = 0,
    this.lastRemarks = '',
    this.lastAction = '',
    this.isFinal = false,
    this.isStale = false,
    this.isKnown = false,
    this.summaryTs = 0,
  });

  final String status;
  final String holder;
  final String initiator;
  final List<String> claimants;
  final int? completion;
  final String lastBy;
  final int lastTs;
  final String lastRemarks;

  /// The `action` of the last event about the record ("Send", "Status
  /// update", "Taken"), empty when none came.
  final String lastAction;

  /// The status is one that ends the record.
  final bool isFinal;

  /// An event came after the last read.
  final bool isStale;

  /// Something was read or received; false for a record nothing is known of.
  final bool isKnown;

  /// The `ts` of the last summary applied; a summary with an older or equal
  /// one is ignored. 0 when none came.
  final int summaryTs;

  bool get isShared => claimants.isNotEmpty;

  /// The web's rule: it was sent on (shared, or with someone else than the
  /// person who raised it).
  bool get isSent =>
      isShared ||
      (holder.isNotEmpty && holder.toLowerCase() != initiator.toLowerCase());

  bool get hasLast => lastBy.isNotEmpty || lastRemarks.isNotEmpty;

  /// Whether the card has a status block at all (the web draws nothing for a
  /// record that was never sent and has no status).
  bool get isShown => isKnown && (status.isNotEmpty || isSent || hasLast);

  /// "With @ana" or "Shared with @ana, @raj".
  String get withText => isShared
      ? 'Shared with ${claimants.map((u) => '@$u').join(', ')}'
      : 'With @$holder';

  RecordLive copyWith({
    String? status,
    String? holder,
    String? initiator,
    List<String>? claimants,
    int? completion,
    String? lastBy,
    int? lastTs,
    String? lastRemarks,
    String? lastAction,
    bool? isFinal,
    bool? isStale,
    int? summaryTs,
  }) => RecordLive(
    status: status ?? this.status,
    holder: holder ?? this.holder,
    initiator: initiator ?? this.initiator,
    claimants: claimants ?? this.claimants,
    completion: completion ?? this.completion,
    lastBy: lastBy ?? this.lastBy,
    lastTs: lastTs ?? this.lastTs,
    lastRemarks: lastRemarks ?? this.lastRemarks,
    lastAction: lastAction ?? this.lastAction,
    isFinal: isFinal ?? this.isFinal,
    isStale: isStale ?? this.isStale,
    isKnown: true,
    summaryTs: summaryTs ?? this.summaryTs,
  );

  /// The state a `record` summary says: status, holder, claimants, completion
  /// and the final flag, with the last change's author and time. The last
  /// remarks belong to an older update and go.
  RecordLive withSummary(RecordSummary r, {String initiator = ''}) =>
      RecordLive(
        status: r.status,
        holder: r.holder,
        initiator: this.initiator.isNotEmpty ? this.initiator : initiator,
        claimants: r.claimants,
        completion: r.completion,
        lastBy: r.by.isNotEmpty ? r.by : lastBy,
        lastTs: r.ts > 0 ? r.ts : lastTs,
        lastAction: lastAction,
        isFinal: r.isFinal,
        isKnown: true,
        summaryTs: r.ts,
      );

  /// From a full `record.actions` read.
  static RecordLive fromState(RecordState s) {
    final last = s.lastUpdate;
    return RecordLive(
      status: s.status,
      holder: s.holder,
      initiator: s.initiator,
      claimants: s.claimants,
      completion: s.completion,
      lastBy: last is Map ? idText(last['by']) : '',
      lastTs: last is Map ? intOf(last['ts']) : 0,
      lastRemarks: last is Map ? idText(last['remarks']) : '',
      isFinal: s.isFinal,
      isKnown: true,
    );
  }

  /// From a `records.mine` row: no last update there, so what a read of
  /// `record.actions` told stays.
  RecordLive withTicket(Ticket t) => RecordLive(
    status: t.status.isNotEmpty ? t.status : status,
    holder: t.holder.isNotEmpty ? t.holder : holder,
    initiator: t.by.isNotEmpty ? t.by : initiator,
    claimants: claimants,
    completion: t.hasStatus ? t.completion : completion,
    lastBy: lastBy,
    lastTs: lastTs,
    lastRemarks: lastRemarks,
    lastAction: lastAction,
    isFinal: t.hasStatus ? t.isFinal : isFinal,
    isStale: isStale,
    isKnown: true,
  );

  /// The answer of my own `record.status` / `record.send`.
  RecordLive withPatch(RecordPatch p, {required String me, required int ts}) =>
      copyWith(
        status: p.status.isNotEmpty ? p.status : status,
        holder: p.holder.isNotEmpty ? p.holder : holder,
        completion: p.completion ?? completion,
        isFinal: p.status.isNotEmpty ? p.isFinal : isFinal,
        claimants: p.holder.isNotEmpty ? const [] : claimants,
        lastBy: me,
        lastTs: ts,
        isStale: false,
      );

  bool sameAs(RecordLive o) =>
      status == o.status &&
      holder == o.holder &&
      initiator == o.initiator &&
      completion == o.completion &&
      lastBy == o.lastBy &&
      lastTs == o.lastTs &&
      lastRemarks == o.lastRemarks &&
      lastAction == o.lastAction &&
      isFinal == o.isFinal &&
      isStale == o.isStale &&
      isKnown == o.isKnown &&
      summaryTs == o.summaryTs &&
      claimants.join(',') == o.claimants.join(',');
}
