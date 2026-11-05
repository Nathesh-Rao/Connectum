/// The words of the Approvals feature, in one place.
class ApprovalsTexts {
  ApprovalsTexts._();

  static const screenTitle = 'Approvals';
  static const tabReview = 'To review';
  static const tabSent = 'Sent by me';
  static const filterPending = 'Pending';
  static const filterAccepted = 'Accepted';
  static const filterRejected = 'Rejected';
  static const filterIgnored = 'Ignored';
  static const retry = 'Retry';

  static const emptyReviewTitle = 'Nothing to review';
  static const emptySentTitle = 'Nothing sent';
  static const emptyReviewMessage =
      'Requests waiting for your answer show up '
      'here.';
  static const emptySentMessage = 'Requests you started show up here.';
  static const emptyHistoryMessage = 'Nothing here yet.';
  static const errorMessage = "Couldn't load your requests.";

  static const detailTitle = 'Request';
  static const from = 'From';
  static const about = 'About';
  static const sent = 'Sent';
  static const answeredBy = 'Answered by';
  static const stage = 'Step';
  static const waitingFor = 'Waiting for';
  static const reasonLabel = 'Reason';

  static const accept = 'Accept';
  static const reject = 'Reject';
  static const returnIt = 'Return';
  static const ignore = 'Ignore';

  static const reasonTitleReject = 'Reject request';
  static const reasonTitleReturn = 'Return to sender';
  static const reasonLabelField = 'Reason';
  static const reasonHint = 'Say why';
  static const reasonRequired =
      'Say why: a form that is sent back or declined needs a reason.';
  static const commentLabel = 'Comment';
  static const commentHint = 'Add a comment (optional)';
  static const allowResubmit = 'Allow them to fix it and send it again';
  static const send = 'Send';

  static const newRequestNotice = 'You have a new request to review.';

  static String typeLabel(String type) => switch (type) {
    'onboarding' => 'Onboarding',
    'associate' => 'Connection',
    'host_transfer' => 'Host transfer',
    'group_invite' => 'Group invite',
    'membership' => 'Membership',
    'submission' => 'Submission',
    'handover' => 'Handover',
    _ => 'Request',
  };

  static String statusLabel(String status) => switch (status) {
    'accepted' => 'Accepted',
    'rejected' => 'Rejected',
    'ignored' => 'Ignored',
    _ => 'Pending',
  };
}
