/// The words of the Tickets feature, in one place.
class TicketsTexts {
  TicketsTexts._();

  static const sectionTodos = 'To-dos';
  static const sectionTickets = 'Tickets';
  static const tabWithMe = 'With me';
  static const tabRaised = 'Raised by me';
  static const filterAll = 'All';
  static const showMore = 'Show more';
  static const retry = 'Retry';

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
  static const historyEmpty = 'No updates yet.';
  static const historyError = "Couldn't load the history.";
  static const byAdmin = 'by an administrator';
  static const sentTo = 'Sent to';
  static const reasonLabel = 'Reason';
  static const filesLabel = 'Files';

  static const ticketMarker = 'Ticket';

  static const sheetSend = 'Send';
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

  /// The light notice after an action: what was done.
  static String done({required String status, String? sentTo}) =>
      sentTo != null && sentTo.isNotEmpty ? 'Sent to @$sentTo.' : '$status.';

  static const assignedRaised = 'A ticket was raised to you.';
  static const assignedMoved = 'A ticket is now with you.';
  static const noTicketNotice = 'That ticket is no longer available.';
}
