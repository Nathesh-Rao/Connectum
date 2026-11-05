import '../../../data/models/ticket.dart';
import '../../../data/socket/call_problem.dart';

/// What the person filled in for one action.
class TicketActionInput {
  const TicketActionInput({
    this.reason = '',
    this.remarks = '',
    this.sendTo = '',
    this.percent = 0,
    this.files = const [],
  });

  final String reason;
  final String remarks;
  final String sendTo;
  final int percent;

  /// Ids of files the server already holds.
  final List<String> files;
}

/// Checks an input against what its action asks for. Null = good to send.
class TicketValidation {
  TicketValidation._();

  static const reasonRequired = 'Say why.';
  static const remarksRequired = 'Add a remark.';
  static const sendToRequired = 'Choose who to send it to.';
  static const percentRange = 'Completion is 0 to 100.';
  static const fileRequired = 'Attach a file.';

  static String? check(TicketAction a, TicketActionInput i) {
    if (a.reason == 'required' && i.reason.trim().isEmpty) {
      return reasonRequired;
    }
    if (a.asksReason &&
        a.reasons.isNotEmpty &&
        i.reason.trim().isNotEmpty &&
        !a.reasons.contains(i.reason)) {
      return reasonRequired;
    }
    if (a.remarks == 'required' && i.remarks.trim().isEmpty) {
      return remarksRequired;
    }
    if (a.asksSendTo && i.sendTo.trim().isEmpty) return sendToRequired;
    if (a.asksPercent && (i.percent < 0 || i.percent > 100)) {
      return percentRange;
    }
    if (a.attachments == 'required' && i.files.isEmpty) return fileRequired;
    return null;
  }
}

/// The `status.update` arguments.
class TicketPayload {
  TicketPayload._();

  /// [expectedStatus] and [expectedAssignee] are exactly what the screen
  /// showed. Only the inputs the action asks for go in. A retry of the same
  /// press passes the same [requestId].
  static Map<String, dynamic> build({
    required int id,
    required TicketAction action,
    required TicketActionInput input,
    required String requestId,
    required String expectedStatus,
    required String expectedAssignee,
  }) {
    final reason = input.reason.trim();
    final remarks = input.remarks.trim();
    return {
      'id': id,
      'action': action.name,
      'expected': {'status': expectedStatus, 'assignee': expectedAssignee},
      'requestId': requestId,
      if (action.asksReason && reason.isNotEmpty) 'reason': reason,
      if (action.asksRemarks && remarks.isNotEmpty) 'remarks': remarks,
      if (action.asksSendTo) 'sendTo': input.sendTo.trim(),
      if (action.asksPercent) 'percent': input.percent.clamp(0, 100),
      if (action.asksFiles && input.files.isNotEmpty) 'files': input.files,
    };
  }
}

/// What the screen does with a failed or finished `status.update`.
class TicketOutcome {
  const TicketOutcome._({
    this.isSuccess = false,
    this.shouldReload = false,
    this.shouldRemoveRow = false,
    this.shouldKeepRequestId = false,
    this.canRetry = false,
    this.shouldKeepForm = false,
  });

  /// Done (a repeat of an update the server already made counts).
  final bool isSuccess;

  /// Read the ticket (and its history) again.
  final bool shouldReload;

  /// The ticket is gone.
  final bool shouldRemoveRow;

  /// A retry is the same update: it reuses the request id.
  final bool shouldKeepRequestId;

  /// A manual Retry button is offered.
  final bool canRetry;

  /// What the person typed stays, to submit again.
  final bool shouldKeepForm;

  static const success = TicketOutcome._(isSuccess: true);

  static TicketOutcome of(CallProblem p) => switch (p.kind) {
    CallProblemKind.duplicate => success,
    CallProblemKind.stale => const TicketOutcome._(
      shouldReload: true,
      shouldKeepForm: true,
    ),
    CallProblemKind.notFound => const TicketOutcome._(shouldRemoveRow: true),
    CallProblemKind.busy ||
    CallProblemKind.rateLimited ||
    CallProblemKind.offline => const TicketOutcome._(
      canRetry: true,
      shouldKeepRequestId: true,
      shouldKeepForm: true,
    ),
    CallProblemKind.unknownOutcome => const TicketOutcome._(
      shouldReload: true,
      canRetry: true,
      shouldKeepRequestId: true,
      shouldKeepForm: true,
    ),
    CallProblemKind.forbidden || CallProblemKind.invalid =>
      const TicketOutcome._(shouldReload: true, shouldKeepForm: true),
    _ => const TicketOutcome._(shouldKeepForm: true),
  };
}
