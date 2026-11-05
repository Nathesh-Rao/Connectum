import 'ids.dart';

/// One row of the summary a submission request carries.
class ApprovalLine {
  const ApprovalLine(this.caption, this.value);

  final String caption;
  final String value;
}

/// One request (`req.list`, `request_created`, `request_resolved`). Every
/// field but [id] may be missing.
class Approval {
  const Approval({
    required this.id,
    this.type = '',
    this.status = pending,
    this.from = '',
    this.fromName = '',
    this.subject = '',
    this.subjectName = '',
    this.approvers = const [],
    this.direction = other,
    this.canRespond = false,
    this.createdTs = 0,
    this.resolvedTs,
    this.resolvedBy,
    this.resolvedByName = '',
    this.resolvedByDesignation,
    this.caption = '',
    this.message = '',
    this.reason = '',
    this.stage,
    this.stages,
    this.lines = const [],
  });

  static const pending = 'pending';
  static const accepted = 'accepted';
  static const rejected = 'rejected';
  static const ignored = 'ignored';
  static const incoming = 'incoming';
  static const outgoing = 'outgoing';
  static const other = 'other';
  static const submissionType = 'submission';

  final int id;

  /// onboarding, associate, host_transfer, group_invite, membership,
  /// submission, handover.
  final String type;
  final String status;
  final String from;
  final String fromName;
  final String subject;
  final String subjectName;
  final List<String> approvers;

  /// incoming, outgoing or other, for the person reading.
  final String direction;
  final bool canRespond;
  final int createdTs;
  final int? resolvedTs;
  final String? resolvedBy;
  final String resolvedByName;
  final String? resolvedByDesignation;

  // What the request's `data` carries.
  final String caption;
  final String message;
  final String reason;
  final int? stage;
  final int? stages;
  final List<ApprovalLine> lines;

  bool get isPending => status == pending;
  bool get isSubmission => type == submissionType;
  bool get isIncoming => direction == incoming;
  bool get isOutgoing => direction == outgoing;
  String get fromLabel => fromName.isEmpty ? from : fromName;
  String get resolvedByLabel =>
      resolvedByName.isNotEmpty ? resolvedByName : (resolvedBy ?? '');

  Approval copyWith({
    String? status,
    bool? canRespond,
    String? direction,
    int? resolvedTs,
    String? resolvedBy,
    String? resolvedByName,
    String? resolvedByDesignation,
    String? reason,
  }) => Approval(
    id: id,
    type: type,
    status: status ?? this.status,
    from: from,
    fromName: fromName,
    subject: subject,
    subjectName: subjectName,
    approvers: approvers,
    direction: direction ?? this.direction,
    canRespond: canRespond ?? this.canRespond,
    createdTs: createdTs,
    resolvedTs: resolvedTs ?? this.resolvedTs,
    resolvedBy: resolvedBy ?? this.resolvedBy,
    resolvedByName: resolvedByName ?? this.resolvedByName,
    resolvedByDesignation: resolvedByDesignation ?? this.resolvedByDesignation,
    caption: caption,
    message: message,
    reason: reason ?? this.reason,
    stage: stage,
    stages: stages,
    lines: lines,
  );

  /// Null when the map has no usable id. [viewer] works out [direction] and
  /// [canRespond] for an event, which does not carry them.
  static Approval? tryParse(Object? json, {String? viewer}) {
    if (json is! Map) return null;
    final id = idNumber(json['id']);
    if (id == null) return null;
    final data = json['data'] is Map ? json['data'] as Map : const {};
    final status = _text(json['status']);
    final from = _text(json['from']);
    final approvers = [
      if (json['approvers'] is List)
        for (final a in json['approvers'] as List) _text(a),
    ];
    var direction = _text(json['direction']);
    var canRespond = json['canRespond'] == true;
    if (direction.isEmpty && viewer != null) {
      final me = viewer.toLowerCase();
      direction = approvers.any((a) => a.toLowerCase() == me)
          ? incoming
          : from.toLowerCase() == me
          ? outgoing
          : other;
      canRespond =
          (status.isEmpty || status == pending) && direction == incoming;
    }
    final summary = data['summary'];
    return Approval(
      id: id,
      type: _text(json['type']),
      status: status.isEmpty ? pending : status,
      from: from,
      fromName: _text(json['fromName']),
      subject: _text(json['subject']),
      subjectName: _text(json['subjectName']),
      approvers: approvers,
      direction: direction.isEmpty ? other : direction,
      canRespond: canRespond,
      createdTs: intOf(json['createdTs']),
      resolvedTs: json['resolvedTs'] == null ? null : intOf(json['resolvedTs']),
      resolvedBy: json['resolvedBy'] == null ? null : _text(json['resolvedBy']),
      resolvedByName: _text(json['resolvedByName']),
      resolvedByDesignation: json['resolvedByDesignation'] == null
          ? null
          : _text(json['resolvedByDesignation']),
      caption: _text(data['caption']),
      message: _text(data['message']),
      reason: _text(data['reason']),
      stage: data['stage'] == null ? null : intOf(data['stage']),
      stages: data['stages'] == null ? null : intOf(data['stages']),
      lines: [
        if (summary is List)
          for (final s in summary)
            if (s is Map) ApprovalLine(_text(s['caption']), _text(s['value'])),
      ],
    );
  }

  static String _text(Object? v) => v is String ? v : idText(v);
}

/// One page of `req.list`.
class ApprovalPage {
  const ApprovalPage(
    this.requests, {
    required this.total,
    required this.hasMore,
  });

  final List<Approval> requests;
  final int total;
  final bool hasMore;

  static ApprovalPage parse(Map<String, dynamic> data) {
    final raw = data['requests'];
    final requests = <Approval>[
      if (raw is List)
        for (final j in raw) ?Approval.tryParse(j),
    ];
    return ApprovalPage(
      requests,
      total: data['total'] == null ? requests.length : intOf(data['total']),
      hasMore: data['hasMore'] == true,
    );
  }
}
