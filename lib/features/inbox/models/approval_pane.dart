import '../../../data/models/approval.dart';
import 'approval_reducer.dart';

/// Where a request stands, for the pane's filter and tag.
enum ApprovalState { pending, approved, rejected, other }

/// The pane's dropdown: All and one entry per [ApprovalState].
enum ApprovalFilter {
  all('All'),
  pending('Pending'),
  approved('Approved'),
  rejected('Rejected'),
  closed('Closed');

  const ApprovalFilter(this.label);

  final String label;
}

/// The Inbox's Approvals pane, as the web's `ApprovalsPane`: which requests
/// show, their state and tag, the count on the button. Pure.
class ApprovalPane {
  ApprovalPane._();

  static const escalateAfter = Duration(days: 3);

  static const noneText = 'There are no approvals.';
  static const noMatchText = 'No approvals are like that.';
  static const errorText = 'Use Refresh to try again';

  static const waitingForYou = 'Waiting for you';
  static const waitingForApproval = 'Waiting for approval';
  static const declined = 'Declined';
  static const approved = 'Approved';

  static ApprovalState stateOf(Approval a) => switch (a.status) {
    Approval.pending => ApprovalState.pending,
    Approval.rejected => ApprovalState.rejected,
    Approval.accepted || 'approved' => ApprovalState.approved,
    _ => ApprovalState.other,
  };

  /// "Waiting for you" is only a request the server lets the person answer.
  static bool isWaitingForMe(Approval a) => a.isPending && a.canRespond;

  /// The tag on a card; empty for a closed one (ignored, withdrawn).
  static String tagOf(Approval a) => switch (stateOf(a)) {
    ApprovalState.pending =>
      isWaitingForMe(a) ? waitingForYou : waitingForApproval,
    ApprovalState.rejected => declined,
    ApprovalState.approved => approved,
    ApprovalState.other => '',
  };

  /// A settled sign-up is not listed (it is a record of the past, not mail).
  static bool isListed(Approval a) => !(a.type == 'onboarding' && !a.isPending);

  /// The button's number: requests waiting for the person. Requests the
  /// person sent are never counted, whoever they wait on.
  static int countOf(Iterable<Approval> all) =>
      all.where(isWaitingForMe).length;

  /// Waiting for the person for more than [escalateAfter]: now minus
  /// `createdTs`, strictly more.
  static bool isEscalated(Approval a, DateTime now) {
    if (!isWaitingForMe(a) || a.createdTs <= 0) return false;
    final age = now.millisecondsSinceEpoch - a.createdTs;
    return age > escalateAfter.inMilliseconds;
  }

  static bool inFilter(Approval a, ApprovalFilter f) => switch (f) {
    ApprovalFilter.all => true,
    ApprovalFilter.pending => stateOf(a) == ApprovalState.pending,
    ApprovalFilter.approved => stateOf(a) == ApprovalState.approved,
    ApprovalFilter.rejected => stateOf(a) == ApprovalState.rejected,
    ApprovalFilter.closed => stateOf(a) == ApprovalState.other,
  };

  /// Every listed request, newest first by `createdTs`.
  static List<Approval> listed(Iterable<Approval> all) =>
      ApprovalReducer.sorted(all.where(isListed));

  /// How many listed requests each filter holds.
  static Map<ApprovalFilter, int> countsOf(Iterable<Approval> all) {
    final rows = all.where(isListed).toList();
    return {
      for (final f in ApprovalFilter.values)
        f: rows.where((a) => inFilter(a, f)).length,
    };
  }

  /// The filters worth offering: All, and each answer that has rows.
  static List<ApprovalFilter> offered(Map<ApprovalFilter, int> counts) => [
    for (final f in ApprovalFilter.values)
      if (f == ApprovalFilter.all || (counts[f] ?? 0) > 0) f,
  ];

  /// The search text narrows the rows by what a card shows.
  static bool matches(Approval a, String query, {String personName = ''}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    bool has(String s) => s.toLowerCase().contains(q);
    return has(kindLabel(a)) ||
        has(titleOf(a)) ||
        has(a.fromLabel) ||
        has(a.from) ||
        has(personName) ||
        has(a.subjectName) ||
        has(a.message) ||
        has(a.reason) ||
        has(tagOf(a)) ||
        has('${a.id}') ||
        a.lines.any((l) => has(l.caption) || has(l.value));
  }

  /// The rows of [filter] that match [query], newest first.
  static List<Approval> rows(
    Iterable<Approval> all, {
    ApprovalFilter filter = ApprovalFilter.all,
    String query = '',
    String Function(Approval)? nameOf,
  }) => [
    for (final a in listed(all))
      if (inFilter(a, filter) &&
          matches(a, query, personName: nameOf?.call(a) ?? ''))
        a,
  ];

  /// "Sign-up", "Connection request", "Form"...
  static String kindLabel(Approval a) => switch (a.type) {
    'onboarding' => 'Sign-up',
    'membership' || 'associate' => 'Connection request',
    'handover' => 'Introduction',
    'group_invite' => 'Group invitation',
    'host_transfer' => 'Transfer',
    'submission' => 'Form',
    _ => 'Request',
  };

  /// The card's title: the form's name for a form, else the kind.
  static String titleOf(Approval a) =>
      a.isSubmission && a.caption.isNotEmpty ? a.caption : kindLabel(a);

  /// The name and value lines of a card: the summary answers and the step of
  /// a form, then who it is from and about and what it says.
  static List<(String, String)> detailRows(Approval a) {
    final out = <(String, String)>[];
    if (a.isSubmission) {
      for (final l in a.lines) {
        if (l.caption.isNotEmpty || l.value.isNotEmpty) {
          out.add((l.caption, l.value));
        }
      }
      final stage = a.stage;
      final stages = a.stages;
      if (stage != null && stages != null) {
        out.add(('Progress', 'Step $stage of $stages'));
      }
    } else {
      if (a.message.isNotEmpty) out.add(('Message', a.message));
      if (a.subjectName.isNotEmpty && a.subject != a.from) {
        out.add(('About', a.subjectName));
      }
    }
    if (a.fromLabel.isNotEmpty) out.add(('From', a.fromLabel));
    if (a.isOutgoing && a.isPending && a.approvers.isNotEmpty) {
      out.add(('Waiting for', a.approvers.join(', ')));
    }
    if (!a.isPending && a.resolvedByLabel.isNotEmpty) {
      out.add(('Answered by', a.resolvedByLabel));
    }
    if (a.reason.isNotEmpty) out.add(('Reason', a.reason));
    return out;
  }
}
