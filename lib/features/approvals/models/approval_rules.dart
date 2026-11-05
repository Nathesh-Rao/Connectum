import '../../../data/models/approval.dart';

enum ApprovalAction {
  accept('accept'),
  reject('reject'),
  returnIt('return'),
  ignore('ignore');

  const ApprovalAction(this.wire);

  /// The `action` the server expects.
  final String wire;
}

/// Which buttons a request shows and what each needs. The server stays the
/// judge and its text is shown when it refuses.
class ApprovalRules {
  ApprovalRules._();

  /// Nothing when the person cannot answer: the request is then read-only.
  static List<ApprovalAction> actionsFor(Approval r) {
    if (!r.canRespond || !r.isPending) return const [];
    return [
      ApprovalAction.accept,
      ApprovalAction.reject,
      if (r.isSubmission) ApprovalAction.returnIt,
      ApprovalAction.ignore,
    ];
  }

  /// "Say why: a form that is sent back or declined needs a reason."
  static bool needsReason(ApprovalAction a) =>
      a == ApprovalAction.reject || a == ApprovalAction.returnIt;

  static bool canSend(ApprovalAction a, String reason) =>
      !needsReason(a) || reason.trim().isNotEmpty;

  /// Rejecting a submission may let its author fix and send it again. A
  /// return always does, so it has no switch.
  static bool offersResubmit(Approval r, ApprovalAction a) =>
      r.isSubmission && a == ApprovalAction.reject;
}
