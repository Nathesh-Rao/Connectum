import 'dart:convert';

/// The one e-mail rule of the app, the same words as the server's
/// `sd_util:valid_email/1` and the web's `emailRule.js`: exactly one `@`,
/// something before it, after it two or more dot-separated names with no empty
/// one, and a last name of two or more letters (or an `xn--` one). No space,
/// control or invisible character anywhere, except a zero-width (non-)joiner
/// inside a name. At most 254 bytes. Unicode addresses are fine.
class EmailRule {
  EmailRule._();

  static const maxBytes = 254;
  static const emptyMessage = 'Enter your email address.';
  static const invalidMessage =
      'Enter a valid email address, like name@company.com.';
  static const tooLongMessage = 'That email address is too long.';
  static const hint = 'Correct the address before a code can be sent.';

  static const _plain = r'[^@\s\p{Z}\p{C}]';
  static const _noDot = r'[^@.\s\p{Z}\p{C}]';
  static const _joiners = '[\u200C\u200D]*';

  static final _pattern = RegExp(
    '^$_plain(?:$_joiners$_plain)*@'
    '(?:$_noDot(?:$_joiners$_noDot)*\\.)+'
    '(?:[\\p{L}\\p{M}](?:$_joiners[\\p{L}\\p{M}])+|xn--[A-Za-z0-9-]+)\$',
    unicode: true,
  );

  /// True when [value] (already trimmed by the caller or not) is an address.
  static bool isValid(String value) {
    final text = value.trim();
    return text.isNotEmpty &&
        utf8.encode(text).length <= maxBytes &&
        _pattern.hasMatch(text);
  }

  /// The words for a wrong address, or null when it is fine. The text is
  /// trimmed first; an empty box says [emptyMessage] unless [isRequired] is
  /// false.
  static String? problem(String value, {bool isRequired = true}) {
    final text = value.trim();
    if (text.isEmpty) return isRequired ? emptyMessage : null;
    if (utf8.encode(text).length > maxBytes) return tooLongMessage;
    return _pattern.hasMatch(text) ? null : invalidMessage;
  }
}
