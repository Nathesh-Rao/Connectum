/// Client checks that mirror the backend: `sd_util:valid_email`,
/// `valid_mobile` (`^\+?[0-9]{7,15}$`) and `valid_username`
/// (`^[a-z0-9][a-z0-9._-]{1,23}$`, the rule the join step applies to the
/// username registered here).
class AuthValidators {
  AuthValidators._();

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _username = RegExp(r'^[a-z0-9][a-z0-9._-]{1,23}$');
  static final _mobile = RegExp(r'^\+[0-9]{7,15}$');
  static final _mobileChars = RegExp(r'^[0-9+\s().-]+$');

  static const mobileError = 'Enter a valid mobile number.';
  static const usernameHint =
      '2 to 24 letters, numbers, dots, dashes or underscores. Saved in lowercase.';

  static String normaliseUsername(String value) => value.trim().toLowerCase();

  static String? email(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'Enter your email address.';
    if (text.length > 254 || !_email.hasMatch(text)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? enterpriseName(String value) =>
      value.trim().isEmpty ? 'Enter the enterprise name.' : null;

  static String? personName(String value) =>
      value.trim().isEmpty ? 'Enter your name.' : null;

  static String? username(String value) {
    final text = normaliseUsername(value);
    if (text.isEmpty) return 'Choose a username.';
    if (!_username.hasMatch(text)) {
      return 'Use 2 to 24 letters, numbers, dots, dashes or underscores, starting with a letter or number.';
    }
    return null;
  }

  /// `+<dial><digits>` from what was typed: a number with a leading "+" or
  /// "00" is read as international, any other is national to [dial] and loses
  /// one leading 0. [error] is null when the value is fine (an empty value is
  /// fine unless [isRequired]).
  static ({String value, String? error}) mobile(
    String typed,
    String dial, {
    required bool isRequired,
  }) {
    final text = typed.trim();
    if (text.isEmpty) {
      return (value: '', error: isRequired ? 'Enter a mobile number.' : null);
    }
    if (!_mobileChars.hasMatch(text)) return (value: '', error: mobileError);
    var digits = text.replaceAll(RegExp(r'\D'), '');
    String full;
    if (text.startsWith('+')) {
      full = '+$digits';
    } else if (digits.startsWith('00')) {
      full = '+${digits.substring(2)}';
    } else {
      if (digits.startsWith('0')) digits = digits.substring(1);
      full = '+$dial$digits';
    }
    return (value: full, error: _mobile.hasMatch(full) ? null : mobileError);
  }
}
