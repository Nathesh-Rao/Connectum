/// The words of the Tickets feature, in one place.
class TicketsTexts {
  TicketsTexts._();

  static const sectionTodos = 'To-dos';
  static const sectionTickets = 'Tickets';
  static const tabWithMe = 'With me';
  static const tabRaised = 'Raised by me';
  static const tabInvolved = 'Involved';
  static const emptyInvolvedTitle = 'Nothing you were involved in';
  static const emptyInvolvedMessage =
      'Records given to you, shared with you or acted on by you show up here.';
  static const filterAll = 'All';
  static const showMore = 'Show more';
  static const retry = 'Retry';
  static const menuLoading = 'Loading…';
  static const menuEmpty = 'No actions available.';
  static const unopenableNotice =
      'You can see this record in the list but not open it yet.';

  static const emptyWithTitle = 'No tickets with you';
  static const emptyWithMessage = 'Tickets that need you show up here.';
  static const emptyRaisedTitle = 'No open tickets raised';
  static const emptyRaisedMessage = 'Tickets you raise show up here.';
  static const emptyFilteredMessage = 'Nothing matches this filter.';
  static const errorMessage = "Couldn't load your tickets.";

  static const withLabel = 'with';
  static const you = 'you';
  static const waitingForApproval = 'Waiting for approval';
  static const waitingForApprovalNote =
      "It can't be acted on until it is approved.";

  static const detailTitle = 'Ticket';
  static const detailError = "Couldn't load this ticket.";
  static const detailGoneTitle = 'Ticket not available';
  static const detailGoneMessage = 'This ticket is no longer available.';
  static const detailNotTicketTitle = 'Not a ticket';
  static const detailNotTicketMessage = "This record has no status.";
  static const withWhom = 'With';
  static const raisedBy = 'Raised by';
  static const completion = 'Completion';
  static const edit = 'Edit';
  static const historyTitle = 'History';
  static const historyEmpty = 'No history yet';
  static const historyRetry = 'Try again';
  static const showLess = 'Show less';
  static String moreCount(int n) => '+$n more';
  static String plusCount(int n) => '+$n';
  static String eventCount(int n) => n == 1 ? '1 event' : '$n events';
  static String hoursValue(String h) => '$h h';
  static const arrowWord = 'to';
  static const historyError = "Couldn't load the history.";
  static const byAdmin = 'by an administrator';
  static const sentTo = 'Sent to';
  static const fromHolder = 'From';
  static const claimed = 'took it';

  /// What an event of the history says it was.
  static String opTitle(String op, {String to = '', String via = ''}) =>
      switch (op) {
        'created' => 'Created',
        'edited' => 'Edited',
        'deleted' => 'Deleted',
        'sent_for_approval' => 'Sent for approval',
        'waiting' => 'Waiting for approval',
        'approved' => 'Approved',
        'declined' => 'Declined',
        'returned' => 'Returned',
        'resubmitted' => 'Resubmitted',
        'approved_final' => 'Approved (final)',
        'sent' =>
          via == 'auto'
              ? (to.isEmpty
                    ? 'Sent automatically'
                    : 'Sent automatically to $to')
              : (to.isEmpty ? 'Sent' : 'Sent to $to'),
        'status' => 'Status updated',
        'reassigned' => to.isEmpty ? 'Reassigned' : 'Reassigned to $to',
        _ => op.replaceAll('_', ' '),
      };
  static const reasonLabel = 'Reason';
  static const filesLabel = 'Files';

  static const ticketMarker = 'Ticket';

  static const sheetSend = 'Send';
  static const statusField = 'Status';
  static const finalSuffix = ' (final)';
  static const commentsField = 'Comments';
  static const commentsHint = 'Add a comment';
  static const hoursField = 'Hours worked';
  static const hoursHint = '0 to 24, for example 2.5';
  static const percentNotSet = 'Not set';
  static const reasonField = 'Reason';
  static const reasonHint = 'Say why';
  static const reasonRequiredHint = 'Say why (required)';
  static const remarksField = 'Remarks';
  static const remarksHint = 'Add a remark';
  static const remarksRequiredHint = 'Add a remark (required)';
  static const sendToField = 'Send to';
  static const sendToPick = 'Choose a person';
  static const sendToTitle = 'Send to';
  static const percentField = 'Completion';
  static const percentHundred = 'Completion becomes 100%';
  static const attach = 'Attach a file';
  static const attachAnother = 'Attach another file';
  static const attachPhoto = 'Take a photo';
  static const attachLibrary = 'Choose a photo';
  static const attachDocument = 'Choose a document';
  static const attachNeedsConnection = 'Attaching a file needs a connection.';
  static const attachMax = 'Attach at most 10 files.';
  static const fileTooLarge = 'That file is over 10 MB. Choose a smaller one.';
  static const attachWait = 'Wait for the upload to finish.';
  static const attachFailed = "A file didn't upload. Retry it or remove it.";
  static const removeFile = 'Remove file';
  static const actionGone = 'That action is no longer available.';

  static String assignHint(String assign) => switch (assign) {
    'keep' => 'It stays with the same person.',
    'raiser' => 'It goes back to the person who raised it.',
    'previous' => 'It goes back to the previous person.',
    'self' => 'You take it.',
    'pick' => 'You choose who gets it.',
    _ => '',
  };

  static String percentValue(int v) => '$v%';
  static String percentWas(int v) => 'Was $v%';
  static String percentSemantics(int v, int min) =>
      'Completion $v percent, minimum $min';
  static String percentLockedSemantics(int v) =>
      'Completion is locked below $v percent';
  static const unknownState = '—';
  static const unknownStateSemantics = 'Status loading';
  static const reopenHint = 'Reopening sets completion to 99%';
  static const closingWarning =
      'Closing this ticket sets completion to 100%. After it is closed, only an administrator can change it.';

  /// The light notice after an action: what was done.
  static String done({required String status, String? sentTo}) =>
      sentTo != null && sentTo.isNotEmpty ? 'Sent to @$sentTo.' : '$status.';

  static const assignedRaised = 'A ticket was raised to you.';
  static const assignedMoved = 'A ticket is now with you.';
  static const saved = 'Saved';
  static const savedWaiting = 'Waiting for approval';
  static const savedNotPosted =
      "Saved, but it couldn't be posted to the chat";
  static String sentOn(List<String> names) => names.length == 1
      ? 'Sent to ${names.first}.'
      : 'Shared with ${names.join(', ')}.';
  static const noTicketNotice = 'That ticket is no longer available.';
}
