import '../../models/ids.dart';
import '../../models/ticket.dart';
import 'sv_source.dart';

/// One record of a structure: a `submissions.list` row (mine, with `canEdit`,
/// labels and files) or a `records.mine` row (received: no `canEdit`, no
/// labels, files or `byName`). Kept in memory only.
class SvRow {
  const SvRow({
    required this.id,
    required this.tstruct,
    required this.by,
    required this.ts,
    this.byName = '',
    this.recordStatus = '',
    this.holder = '',
    this.claimants = const [],
    this.completion,
    this.values = const {},
    this.labels = const {},
    this.files = const {},
    this.canEdit = false,
    this.isReceived = false,
  });

  final int id;
  final String tstruct;
  final String by;
  final String byName;
  final int ts;

  /// The record's own state: `pending`, `rejected`, `approved` or empty.
  final String recordStatus;
  final String holder;
  final List<String> claimants;
  final int? completion;
  final Map<String, dynamic> values;
  final Map<String, dynamic> labels;
  final Map<String, dynamic> files;

  /// Only a `submissions.list` row can say so; a received record never can.
  final bool canEdit;
  final bool isReceived;

  /// `Waiting for approval` / `Declined` / `Approved` / `Recorded`.
  String get approval => switch (recordStatus.toLowerCase()) {
    'pending' => 'Waiting for approval',
    'rejected' => 'Declined',
    'approved' => 'Approved',
    _ => 'Recorded',
  };

  /// The web's **With**: claimants, else the holder, else who raised it.
  String get withWhom => claimants.isNotEmpty
      ? claimants.join(', ')
      : holder.isNotEmpty
      ? holder
      : by;

  SvRow copyWith({
    String? recordStatus,
    String? holder,
    List<String>? claimants,
    int? completion,
    int? ts,
    Map<String, dynamic>? values,
  }) => SvRow(
    id: id,
    tstruct: tstruct,
    by: by,
    byName: byName,
    ts: ts ?? this.ts,
    recordStatus: recordStatus ?? this.recordStatus,
    holder: holder ?? this.holder,
    claimants: claimants ?? this.claimants,
    completion: completion ?? this.completion,
    values: values ?? this.values,
    labels: labels,
    files: files,
    canEdit: canEdit,
    isReceived: isReceived,
  );

  /// The record as the record screens and the card state know it.
  Ticket toTicket(SvSource source) => Ticket(
    id: id,
    by: by,
    ts: ts,
    tstruct: tstruct,
    values: values,
    recordStatus: recordStatus,
    holder: holder,
    completion: completion ?? 0,
    form: source.form,
  );

  static Map<String, dynamic> _map(Object? raw) => raw is Map
      ? {for (final e in raw.entries) idText(e.key): e.value}
      : const {};

  static SvRow? tryParse(Object? raw, {required bool isReceived}) {
    if (raw is! Map) return null;
    final id = idNumber(raw['id']);
    if (id == null) return null;
    final completion = raw['completion'];
    return SvRow(
      id: id,
      tstruct: idText(raw['tstruct']),
      by: idText(raw['by']),
      byName: idText(raw['byName']),
      ts: intOf(raw['ts']),
      recordStatus: idText(raw['status']),
      holder: idText(raw['holder']),
      claimants: [
        if (raw['claimants'] is List)
          for (final c in raw['claimants'] as List)
            if (idText(c).isNotEmpty) idText(c),
      ],
      completion: completion == null ? null : intOf(completion).clamp(0, 100),
      values: _map(raw['values']),
      labels: _map(raw['labels']),
      files: _map(raw['files']),
      canEdit: !isReceived && raw['canEdit'] == true,
      isReceived: isReceived,
    );
  }
}

/// One page of `submissions.list` or `records.mine`.
class SvPage {
  const SvPage({
    required this.rows,
    required this.received,
    required this.hasMore,
    this.next,
    this.total = 0,
  });

  final List<SvRow> rows;

  /// Rows in the reply, readable or not: paging continues at
  /// `offset + received` (a page may be short while `hasMore` is true).
  final int received;
  final bool hasMore;

  /// Only `raised` and `team` give a real one; null for the other lists.
  final int? next;
  final int total;

  static SvPage parse(Map<String, dynamic> data, {required bool isReceived}) {
    final list = data['submissions'];
    final rows = [
      if (list is List)
        for (final r in list) ?SvRow.tryParse(r, isReceived: isReceived),
    ];
    return SvPage(
      rows: rows,
      received: list is List ? list.length : 0,
      hasMore: data['hasMore'] == true,
      next: data['next'] == null ? null : intOf(data['next']),
      total: data['total'] == null ? rows.length : intOf(data['total']),
    );
  }
}
