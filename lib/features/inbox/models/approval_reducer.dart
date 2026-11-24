import '../../../data/models/approval.dart';

/// Keeps the Approvals list right when an event or an answer arrives. Pure.
class ApprovalReducer {
  ApprovalReducer._();

  /// Newest first.
  static List<Approval> sorted(Iterable<Approval> list) {
    final out = list.toList();
    out.sort((a, b) {
      final byTime = b.createdTs.compareTo(a.createdTs);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    return out;
  }

  /// Waiting on me, or (history) once waiting on me. An administrator who may
  /// answer a request that was not sent to them sees it here too.
  static bool inReview(Approval r) => r.isIncoming || r.canRespond;
  static bool inSent(Approval r) => r.isOutgoing;

  /// `request_created`: joins a pending list once.
  static List<Approval> applyCreated(
    List<Approval> list,
    Approval request, {
    required String status,
  }) {
    if (status != Approval.pending && status != 'all') return list;
    if (list.any((r) => r.id == request.id)) return list;
    return sorted([...list, request]);
  }

  /// `request_resolved`: the card stays and shows its new state. Only the
  /// answer's fields are taken; the event does not know what the viewer may
  /// do, so nobody can answer it again.
  static List<Approval> applyResolved(List<Approval> list, Approval request) =>
      [
        for (final r in list)
          r.id == request.id
              ? r.copyWith(
                  status: request.status,
                  canRespond: false,
                  resolvedTs: request.resolvedTs,
                  resolvedBy: request.resolvedBy,
                  resolvedByName: request.resolvedByName.isEmpty
                      ? null
                      : request.resolvedByName,
                  resolvedByDesignation: request.resolvedByDesignation,
                  reason: request.reason.isEmpty ? null : request.reason,
                )
              : r,
      ];

  static List<Approval> remove(List<Approval> list, int id) => [
    for (final r in list)
      if (r.id != id) r,
  ];

  /// A first page read again. Cards answered here ([kept]) that the page no
  /// longer lists stay until the person leaves or changes the filter.
  static List<Approval> refreshed(
    List<Approval> fresh,
    List<Approval> old,
    Set<int> kept,
  ) {
    final ids = {for (final r in fresh) r.id};
    return sorted([
      ...fresh,
      for (final r in old)
        if (kept.contains(r.id) && !ids.contains(r.id)) r,
    ]);
  }

  static List<Approval> appended(List<Approval> shown, List<Approval> page) {
    final ids = {for (final r in shown) r.id};
    return [
      ...shown,
      for (final r in page)
        if (!ids.contains(r.id)) r,
    ];
  }
}
