import 'ids.dart';
import 'record_state.dart';
import 'ticket.dart';

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
      claimants.join(',') == o.claimants.join(',');
}
