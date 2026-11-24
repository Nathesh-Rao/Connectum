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

/// What one `req.respond` carries. Built only by [ApprovalRules.answerFor].
class ApprovalAnswer {
  const ApprovalAnswer(
    this.action, {
    this.reason,
    this.comment,
    this.allowResubmit,
  });

  final ApprovalAction action;
  final String? reason;
  final String? comment;
  final bool? allowResubmit;
}

/// Which buttons a request shows and what each answer needs. The server stays
/// the judge (`canRespond`) and its text is shown when it refuses.
class ApprovalRules {
  ApprovalRules._();

  /// `reason` and `comment` are trimmed text of at most this many characters.
  static const maxText = 500;

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

  /// The server refuses to decline or return a form without a reason. A
  /// sign-up or a connection may be declined without one.
  static bool needsReason(Approval r, ApprovalAction a) => switch (a) {
    ApprovalAction.returnIt => true,
    ApprovalAction.reject => r.isSubmission,
    _ => false,
  };

  /// Declining a form and returning one ask for the reason first; the other
  /// answers go out on one tap.
  static bool opensSheet(Approval r, ApprovalAction a) => needsReason(r, a);

  static bool canSend(Approval r, ApprovalAction a, String reason) =>
      !needsReason(r, a) || clip(reason).isNotEmpty;

  /// Declining a form may let its author fix and send it again, off unless
  /// the person turns it on. A return always does, so it has no switch.
  static bool offersResubmit(Approval r, ApprovalAction a) =>
      r.isSubmission && a == ApprovalAction.reject;

  /// Trimmed and cut to [maxText].
  static String clip(String text) {
    final t = text.trim();
    return t.length <= maxText ? t : t.substring(0, maxText).trimRight();
  }

  /// The answer to send, or null when a needed reason is missing. Accept and
  /// ignore carry no reason; `allowResubmit` goes only with declining a form.
  static ApprovalAnswer? answerFor(
    Approval r,
    ApprovalAction a, {
    String reason = '',
    String comment = '',
    bool allowResubmit = false,
  }) {
    if (!canSend(r, a, reason)) return null;
    final why = clip(reason);
    final note = clip(comment);
    final hasReason =
        a == ApprovalAction.reject || a == ApprovalAction.returnIt;
    return ApprovalAnswer(
      a,
      reason: hasReason && why.isNotEmpty ? why : null,
      comment: note.isEmpty ? null : note,
      allowResubmit: offersResubmit(r, a) ? allowResubmit : null,
    );
  }
}
