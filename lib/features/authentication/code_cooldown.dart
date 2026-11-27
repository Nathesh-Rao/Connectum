import 'package:connectum/data/models/models.dart';

/// When a refused code request may be tried again, kept per action and e-mail
/// for the life of the app, so the wait survives moving between the auth
/// screens and back. [now] is replaceable for tests.
class CodeCooldown {
  CodeCooldown._();

  static DateTime Function() now = DateTime.now;
  static const liveSecondsLimit = 120;

  static final _ends = <String, DateTime>{};

  static String _key(AuthFlow flow, String email) =>
      '${flow.name}|${email.trim().toLowerCase()}';

  static void start(AuthFlow flow, String email, int seconds) {
    if (seconds <= 0) return;
    _ends[_key(flow, email)] = now().add(Duration(seconds: seconds));
  }

  /// Whole seconds left (rounded up), 0 when the wait is over.
  static int secondsLeft(AuthFlow flow, String email) {
    final key = _key(flow, email);
    final end = _ends[key];
    if (end == null) return 0;
    final ms = end.difference(now()).inMilliseconds;
    if (ms <= 0) {
      _ends.remove(key);
      return 0;
    }
    return (ms / 1000).ceil();
  }

  /// "42 s" up to two minutes, then whole minutes rounded up.
  static String words(int seconds) => seconds <= liveSecondsLimit
      ? '$seconds s'
      : '${(seconds / 60).ceil()} min';

  static String sentence(int seconds) => 'Try again in ${words(seconds)}';

  static void reset() => _ends.clear();
}
