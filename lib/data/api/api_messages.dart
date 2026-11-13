import 'api_client.dart';

/// Plain-words text for the errors the sign-in flows can return.
class ApiMessages {
  ApiMessages._();

  /// Wrong or unset password: one message, so it never says which part was
  /// wrong (the server answers the same either way).
  static const wrongPassword =
      'That email and password do not match. You can sign in with an emailed code instead.';

  static const passwordLocked =
      'Too many wrong passwords. Use an emailed code, or try again in a few minutes.';

  static String ofPasswordSignIn(ApiException e) => switch (e.code) {
    'invalid_credentials' => wrongPassword,
    'rate_limited' => passwordLocked,
    _ => of(e),
  };

  static String of(Object error) {
    if (error is! ApiException) {
      return 'Something went wrong. Please try again.';
    }
    return switch (error.code) {
      'network' when error.status == 503 =>
        'The server is restarting or busy. Wait a few seconds and try again.',
      'network' || 'bad_response' =>
        "Can't reach the server. Check your connection and try again.",
      'no_account' => 'There is no account for that email. Create one first.',
      'otp_invalid' =>
        error.message.isNotEmpty ? error.message : "That code isn't right.",
      'otp_locked' => 'Too many wrong codes. Ask for a new code.',
      'rate_limited' => 'Too many attempts. Wait a minute and try again.',
      'invalid' =>
        error.message.isNotEmpty ? error.message : 'Check what you entered.',
      'exists' => 'An account with that email already exists. Sign in instead.',
      'invalid_mobile' => 'Enter a valid mobile number.',
      'no_pending_setup' => 'That setup has expired. Start again.',
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
