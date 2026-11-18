/// What is reported for an unexpected error: its type and a cleaned message,
/// never the raw exception text.
class SanitizedError implements Exception {
  const SanitizedError(this.type, this.message);

  final String type;
  final String message;

  @override
  String toString() => message.isEmpty ? type : '$type: $message';
}

class CrashSanitizer {
  CrashSanitizer._();

  static const maxLength = 300;

  static final _bearer = RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+');
  static final _jwt = RegExp(
    r'[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*',
  );
  static final _url = RegExp(r'''[A-Za-z][A-Za-z0-9+.-]*://[^\s'"<>)]+''');
  static final _secret = RegExp(
    r'(password|passwd|pwd|otp|pin|token|secret|authorization|api[_-]?key)\s*[=:]\s*\S+',
    caseSensitive: false,
  );
  static final _email = RegExp(
    r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
  );
  static final _blob = RegExp(r'[A-Za-z0-9+/_-]{40,}={0,2}');
  static final _hex24 = RegExp(
    r'(?<![0-9A-Za-z])[0-9a-fA-F]{24}(?![0-9A-Za-z])',
  );
  static final _digits = RegExp(r'\+?\d[\d\s().-]{6,}\d|\d{8,}');

  static String clean(String input) {
    var s = input;
    s = s.replaceAll(_bearer, 'Bearer ***');
    s = s.replaceAll(_url, '<url>');
    s = s.replaceAll(_jwt, '<jwt>');
    s = s.replaceAllMapped(_secret, (m) => '${m[1]}=***');
    s = s.replaceAll(_email, '<email>');
    s = s.replaceAll(_blob, '<blob>');
    s = s.replaceAll(_hex24, '<id>');
    s = s.replaceAllMapped(_digits, (m) {
      final count = RegExp(r'\d').allMatches(m[0]!).length;
      return count >= 8 ? '<num>' : m[0]!;
    });
    return s.length > maxLength ? s.substring(0, maxLength) : s;
  }
}
