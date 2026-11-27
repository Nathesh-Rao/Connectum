import 'package:connectum/data/models/models.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../../data/records/record_commands.dart';

/// What the person filled in on the status sheet.
class StatusInput {
  const StatusInput({
    this.status = '',
    this.comments = '',
    this.percent,
    this.hours = '',
    this.files = const [],
  });

  final String status;
  final String comments;

  /// Null = not given.
  final int? percent;

  /// As typed ("2.5"); empty = not given.
  final String hours;

  /// Ids of files the server already holds.
  final List<String> files;
}

/// What the person filled in on the send sheet.
class SendInput {
  const SendInput({
    this.via = '',
    this.person = '',
    this.value = '',
    this.reason = '',
    this.remarks = '',
    this.files = const [],
  });

  static const viaUser = 'user';
  static const viaDesignation = 'designation';
  static const viaCategory = 'category';
  static const viaInitiator = 'initiator';
  static const viaAssignor = 'assignor';

  final String via;
  final String person;
  final String value;
  final String reason;
  final String remarks;
  final List<String> files;
}

/// The phone's own checks. They use the BE's wording; the server stays the
/// judge and nothing here blocks on a rule only the server knows.
class RecordValidation {
  RecordValidation._();

  static const commentsRequired = 'Add your comments.';
  static const completionRequired = 'Enter the completion.';
  static const hoursRequired = 'Enter the hours worked.';
  static const fileRequired = 'Attach a file.';
  static const statusRequired = 'Choose one of the statuses of this record.';
  static const completionRange = 'Completion is 0 to 100.';
  static const completionDown = 'Completion cannot go down.';
  static const closingOnly =
      '100% completion is only for a closing status. Choose a closing status.';
  static const hoursRange =
      'Hours worked must be a number from 0 to 24, with at most two decimals.';
  static const commentsLong = 'Comments are at most 1,000 characters.';
  static const sendToRequired = 'Choose who to send it to.';
  static const textLong = 'Reason and remarks are at most 1,000 characters.';
  static const tooManyFiles = 'Attach at most 10 files.';

  static final _hours = RegExp(r'^\d+([.,]\d{1,2})?$');

  /// The hours as a number, or null when [text] is not 0 to 24 with at most
  /// two decimals.
  static double? hoursOf(String text) {
    final t = text.trim();
    if (!_hours.hasMatch(t)) return null;
    final v = double.tryParse(t.replaceAll(',', '.'));
    return v == null || v < 0 || v > RecordLimits.maxHours ? null : v;
  }

  /// The first thing wrong with a status update; null = good to send.
  static String? status(RecordState s, StatusInput i) {
    if (i.status.isEmpty || !s.statuses.contains(i.status)) {
      return statusRequired;
    }
    if (i.comments.length > RecordLimits.maxText) return commentsLong;
    if (s.isCommentsRequired && i.comments.trim().isEmpty) {
      return commentsRequired;
    }
    final p = i.percent;
    if (p != null && (p < 0 || p > 100)) return completionRange;
    if (s.isCompletionRequired && p == null) return completionRequired;
    if (p != null && !s.isAdmin) {
      final floor = [
        s.completion ?? 0,
        s.minCompletion ?? 0,
      ].reduce((a, b) => a > b ? a : b);
      if (p < floor) return completionDown;
    }
    if (p != null &&
        p > 99 &&
        s.finalStatuses.isNotEmpty &&
        !s.finalStatuses.contains(i.status)) {
      return closingOnly;
    }
    if (i.hours.trim().isNotEmpty && hoursOf(i.hours) == null) {
      return hoursRange;
    }
    if (s.isHoursRequired && i.hours.trim().isEmpty) return hoursRequired;
    if (i.files.length > RecordLimits.maxFiles) return tooManyFiles;
    if (s.isFilesRequired && i.files.isEmpty) return fileRequired;
    return null;
  }

  /// The first thing wrong with a send; null = good to send.
  static String? send(SendInput i) {
    final needsPerson = i.via == SendInput.viaUser;
    final needsValue =
        i.via == SendInput.viaDesignation || i.via == SendInput.viaCategory;
    if (i.via.isEmpty ||
        (needsPerson && i.person.trim().isEmpty) ||
        (needsValue && i.value.trim().isEmpty)) {
      return sendToRequired;
    }
    if (i.reason.length > RecordLimits.maxText ||
        i.remarks.length > RecordLimits.maxText) {
      return textLong;
    }
    if (i.files.length > RecordLimits.maxFiles) return tooManyFiles;
    return null;
  }
}

/// The `record.status` and `record.send` arguments. Only what was given goes
/// in. A retry of the same press passes the same [requestId]; a new press
/// makes a new one.
class RecordPayload {
  RecordPayload._();

  static Map<String, dynamic> status({
    required int id,
    required StatusInput input,
    required String requestId,
    Map<String, dynamic> expected = const {},
  }) {
    final comments = input.comments.trim();
    final hours = input.hours.trim();
    return {
      'id': id,
      'status': input.status,
      if (comments.isNotEmpty) 'comments': comments,
      if (input.percent != null) 'percent': input.percent!.clamp(0, 100),
      if (hours.isNotEmpty) 'hours': hours.replaceAll(',', '.'),
      if (input.files.isNotEmpty) 'files': input.files,
      if (expected.isNotEmpty) 'expected': expected,
      'requestId': requestId,
    };
  }

  static Map<String, dynamic> send({
    required int id,
    required SendInput input,
    required String requestId,
    Map<String, dynamic> expected = const {},
  }) {
    final reason = input.reason.trim();
    final remarks = input.remarks.trim();
    return {
      'id': id,
      'via': input.via,
      if (input.via == SendInput.viaUser) 'person': input.person.trim(),
      if (input.via == SendInput.viaDesignation ||
          input.via == SendInput.viaCategory)
        'value': input.value.trim(),
      if (reason.isNotEmpty) 'reason': reason,
      if (remarks.isNotEmpty) 'remarks': remarks,
      if (input.files.isNotEmpty) 'files': input.files,
      if (expected.isNotEmpty) 'expected': expected,
      'requestId': requestId,
    };
  }
}

/// What the screen does with a failed or finished record action. Decided by
/// the error `code`, never by its message.
class TicketOutcome {
  const TicketOutcome._({
    this.isSuccess = false,
    this.shouldReload = false,
    this.shouldLeave = false,
    this.shouldKeepRequestId = false,
    this.canRetry = false,
    this.shouldRetryOnce = false,
    this.shouldBackOff = false,
  });

  /// Done (a repeat of an update the server already made counts).
  final bool isSuccess;

  /// Read the record (`record.actions` and the history) again.
  final bool shouldReload;

  /// The record is gone or no longer visible: close the screen and refresh
  /// the list.
  final bool shouldLeave;

  /// A retry is the same intent: it reuses the request id.
  final bool shouldKeepRequestId;

  /// A manual Retry button is offered.
  final bool canRetry;

  /// `busy`: one automatic retry after a short wait, same request id.
  final bool shouldRetryOnce;

  /// `rate_limited` (no `retryAfter`): wait a little before a retry.
  final bool shouldBackOff;

  static const success = TicketOutcome._(isSuccess: true);

  static TicketOutcome of(CallProblem p) => switch (p.kind) {
    CallProblemKind.duplicate => success,
    CallProblemKind.stale => const TicketOutcome._(shouldReload: true),
    CallProblemKind.notFound => const TicketOutcome._(shouldLeave: true),
    CallProblemKind.busy => const TicketOutcome._(
      canRetry: true,
      shouldKeepRequestId: true,
      shouldRetryOnce: true,
    ),
    CallProblemKind.rateLimited => const TicketOutcome._(
      canRetry: true,
      shouldKeepRequestId: true,
      shouldBackOff: true,
    ),
    CallProblemKind.offline => const TicketOutcome._(
      canRetry: true,
      shouldKeepRequestId: true,
    ),
    CallProblemKind.unknownOutcome => const TicketOutcome._(
      shouldReload: true,
      canRetry: true,
      shouldKeepRequestId: true,
    ),
    CallProblemKind.forbidden => const TicketOutcome._(shouldReload: true),
    _ => const TicketOutcome._(),
  };
}
