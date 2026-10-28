import 'api_client.dart';

/// Plain-words text for the errors the sign-in flows can return.
class ApiMessages {
  ApiMessages._();

  static String of(Object error) {
    if (error is! ApiException) {
      return 'Something went wrong. Please try again.';
    }
    return switch (error.code) {
      'network' || 'bad_response' =>
        "Can't reach the server. Check your connection and try again.",
      'no_account' => 'There is no account for that email. Create one first.',
      'otp_invalid' =>
        error.message.isNotEmpty ? error.message : "That code isn't right.",
      'otp_locked' => 'Too many wrong codes. Ask for a new code.',
      'rate_limited' => 'Too many tries. Wait a few minutes and try again.',
      'invalid' =>
        error.message.isNotEmpty ? error.message : 'Check what you entered.',
      'exists' => 'An account with that email already exists. Sign in instead.',
      'no_pending' => 'That sign-up has expired. Start again.',
      'unauthenticated' => 'Your session has ended. Please sign in again.',
      'pending_approval' =>
        'Your request to join is still waiting for approval.',
      'rejected' => 'Your request to join was not approved.',
      'account_inactive' =>
        'This account is inactive. Contact your administrator.',
      'not_member' => "You're not a member of that enterprise.",
      'already' => 'You are already connected to this enterprise.',
      'not_found' =>
        error.message.isNotEmpty ? error.message : 'Nothing was found.',
      _ =>
        error.message.isNotEmpty
            ? error.message
            : 'Something went wrong. Please try again.',
    };
  }
}
