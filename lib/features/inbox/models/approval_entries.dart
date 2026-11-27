import 'package:connectum/data/models/models.dart';

/// Which side of the Me / My Team toggle.
enum ApprovalSide { me, team }

/// The five primary chips of the Approvals tab, in the order shown.
enum ApprovalPrimary {
  all('All'),
  pending('Pending'),
  approved('Approved'),
  requests('Requests'),
  rejected('Rejected');

  const ApprovalPrimary(this.label);

  final String label;
}

/// Where a request stands for the chips. A return is stored as a rejection
/// (`returned: true`); a dismissed or withdrawn request is [other]: it is in
/// no entry and is not listed.
enum ApprovalState { pending, approved, rejected, other }

/// The entries a chip is made of, as the web's `ENTRIES`
/// (`approvalFilters.js`). There is no "Sent to team" and no "Approved by
/// team".
enum ApprovalEntry {
  sentToMe('Sent to me', ApprovalSide.me),
  sentByMe('Sent by me', ApprovalSide.me),
  sentByTeam('Sent by team', ApprovalSide.team),
  pendingByMe('Pending by me', ApprovalSide.me),
  pendingWithMe('Pending with me', ApprovalSide.me),
  pendingToTeam('Pending to team', ApprovalSide.team),
  approvedByMe('Approved by me', ApprovalSide.me),
  approvedForMe('Approved for me', ApprovalSide.me),
  approvedToTeam('Approved to team', ApprovalSide.team),
  rejectedByMe('Rejected by me', ApprovalSide.me),
  rejectedForMe('Rejected for me', ApprovalSide.me),
  rejectedToTeam('Rejected to team', ApprovalSide.team);

  const ApprovalEntry(this.label, this.side);

  final String label;
  final ApprovalSide side;
}

/// The person and their direct reports, lower case.
class ApprovalWho {
  const ApprovalWho({this.me = '', this.team = const {}});

  final String me;
  final Set<String> team;

  static ApprovalWho of(String me, Iterable<String> team) => ApprovalWho(
    me: me.trim().toLowerCase(),
    team: {
      for (final t in team)
        if (t.trim().isNotEmpty) t.trim().toLowerCase(),
    },
  );
}

/// The entry rules of the Approvals tab. Pure; the backend's words
/// (`approvalFilters.js`, "Connectum Inbox" doc section 4).
class ApprovalEntries {
  ApprovalEntries._();

  static ApprovalState stateOf(Approval a) =>
      switch (a.status.trim().toLowerCase()) {
        'pending' => ApprovalState.pending,
        'rejected' || 'declined' || 'returned' => ApprovalState.rejected,
        'accepted' || 'approved' => ApprovalState.approved,
        _ => ApprovalState.other,
      };

  /// Every request that is waiting, approved, declined or returned; a
  /// dismissed or withdrawn one is not listed anywhere, and neither is a
  /// sign-up that is no longer pending (the web's `HashInboxModal`).
  static bool isListed(Approval a) {
    final s = stateOf(a);
    if (s == ApprovalState.other) return false;
    return a.type != 'onboarding' || s == ApprovalState.pending;
  }

  /// A return counts as a rejection and says so.
  static bool isReturned(Approval a) =>
      a.returned || a.status.trim().toLowerCase() == 'returned';

  /// It waits for this person's answer: pending and the server lets them.
  static bool waitsForMe(Approval a) => a.isPending && a.canRespond;

  static bool _toMe(Approval a) => a.isIncoming || waitsForMe(a);
  static bool _mine(Approval a) => a.isOutgoing;
  static bool _byTeam(Approval a, ApprovalWho w) => w.team.contains(a.fromUser);
  static bool _answeredByMe(Approval a, ApprovalWho w) {
    final by = (a.resolvedBy ?? '').trim().toLowerCase();
    return by.isNotEmpty && by == w.me;
  }

  /// Is [a] in [e]?
  static bool inEntry(Approval a, ApprovalEntry e, ApprovalWho w) {
    final s = stateOf(a);
    // Dismissed, withdrawn or a settled sign-up: in none of the entries.
    if (!isListed(a)) return false;
    return switch (e) {
      ApprovalEntry.sentToMe => _toMe(a),
      ApprovalEntry.sentByMe => _mine(a),
      ApprovalEntry.sentByTeam => _byTeam(a, w),
      ApprovalEntry.pendingByMe => s == ApprovalState.pending && _mine(a),
      ApprovalEntry.pendingWithMe =>
        s == ApprovalState.pending && waitsForMe(a),
      ApprovalEntry.pendingToTeam =>
        s == ApprovalState.pending && waitsForMe(a) && _byTeam(a, w),
      ApprovalEntry.approvedByMe =>
        s == ApprovalState.approved && _answeredByMe(a, w),
      ApprovalEntry.approvedForMe => s == ApprovalState.approved && _mine(a),
      ApprovalEntry.approvedToTeam =>
        s == ApprovalState.approved && _answeredByMe(a, w) && _byTeam(a, w),
      ApprovalEntry.rejectedByMe =>
        s == ApprovalState.rejected && _answeredByMe(a, w),
      ApprovalEntry.rejectedForMe => s == ApprovalState.rejected && _mine(a),
      ApprovalEntry.rejectedToTeam =>
        s == ApprovalState.rejected && _answeredByMe(a, w) && _byTeam(a, w),
    };
  }

  /// The entries a chip holds on a side.
  static List<ApprovalEntry> entriesOf(
    ApprovalPrimary chip,
    ApprovalSide side,
  ) {
    const me = {
      ApprovalPrimary.all: [
        ApprovalEntry.sentToMe,
        ApprovalEntry.sentByMe,
        ApprovalEntry.pendingByMe,
        ApprovalEntry.pendingWithMe,
        ApprovalEntry.approvedByMe,
        ApprovalEntry.approvedForMe,
        ApprovalEntry.rejectedByMe,
        ApprovalEntry.rejectedForMe,
      ],
      ApprovalPrimary.pending: [
        ApprovalEntry.pendingByMe,
        ApprovalEntry.pendingWithMe,
      ],
      ApprovalPrimary.approved: [
        ApprovalEntry.approvedByMe,
        ApprovalEntry.approvedForMe,
      ],
      ApprovalPrimary.requests: [
        ApprovalEntry.sentToMe,
        ApprovalEntry.sentByMe,
      ],
      ApprovalPrimary.rejected: [
        ApprovalEntry.rejectedByMe,
        ApprovalEntry.rejectedForMe,
      ],
    };
    const team = {
      ApprovalPrimary.all: [
        ApprovalEntry.sentByTeam,
        ApprovalEntry.pendingToTeam,
        ApprovalEntry.approvedToTeam,
        ApprovalEntry.rejectedToTeam,
      ],
      ApprovalPrimary.pending: [ApprovalEntry.pendingToTeam],
      ApprovalPrimary.approved: [ApprovalEntry.approvedToTeam],
      ApprovalPrimary.requests: [ApprovalEntry.sentByTeam],
      ApprovalPrimary.rejected: [ApprovalEntry.rejectedToTeam],
    };
    return (side == ApprovalSide.team ? team : me)[chip] ?? const [];
  }

  /// Is [a] in the chip on [side]: listed, and in any of its entries.
  static bool inChip(
    Approval a,
    ApprovalPrimary chip,
    ApprovalSide side,
    ApprovalWho w,
  ) => isListed(a) && entriesOf(chip, side).any((e) => inEntry(a, e, w));

  /// The requests of the chip on [side].
  static List<Approval> rowsOf(
    Iterable<Approval> rows,
    ApprovalPrimary chip,
    ApprovalSide side,
    ApprovalWho w,
  ) => [
    for (final a in rows)
      if (inChip(a, chip, side, w)) a,
  ];

  /// The number on each chip for [side], over [rows].
  static Map<ApprovalPrimary, int> countsOf(
    Iterable<Approval> rows,
    ApprovalSide side,
    ApprovalWho w,
  ) {
    final list = rows.toList();
    return {
      for (final c in ApprovalPrimary.values)
        c: rowsOf(list, c, side, w).length,
    };
  }
}
