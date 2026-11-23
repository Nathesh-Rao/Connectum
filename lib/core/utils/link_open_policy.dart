import '../config/app_config.dart';

enum LinkOpenMode { inApp, external, blocked }

/// Hosts that open inside the app besides the server's own, for links to the
/// enterprise's own systems (Axpert, private cloud). Lower case, no port.
class LinkHosts {
  LinkHosts._();

  static const Set<String> extra = {};

  static Set<String> get trusted => {...AppConfig.trustedHosts, ...extra};

  /// Hosts a plain http link may point at (the dev machine).
  static Set<String> get cleartext => {AppConfig.devHost};
}

/// Decides where a link opens. Pure: the same text and hosts always give the
/// same answer.
class LinkOpenPolicy {
  LinkOpenPolicy._();

  static const blockedMessage = "This link can't be opened from the app.";

  static const _handoff = {'mailto', 'tel', 'sms'};

  static String normalizeHost(String host) {
    var h = host.trim().toLowerCase();
    while (h.endsWith('.')) {
      h = h.substring(0, h.length - 1);
    }
    return h;
  }

  static LinkOpenMode decide(
    String url,
    Set<String> trustedHosts, {
    Set<String> cleartextHosts = const {},
  }) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return LinkOpenMode.blocked;
    final scheme = uri.scheme.toLowerCase();
    if (_handoff.contains(scheme)) return LinkOpenMode.external;
    if (scheme != 'https' && scheme != 'http') return LinkOpenMode.blocked;
    final host = normalizeHost(uri.host);
    if (host.isEmpty) return LinkOpenMode.blocked;
    final trusted = {for (final h in trustedHosts) normalizeHost(h)};
    if (scheme == 'http') {
      final allowed = {for (final h in cleartextHosts) normalizeHost(h)};
      if (!allowed.contains(host)) return LinkOpenMode.blocked;
    }
    // A name before the "@" is how a look-alike address hides its real host.
    if (uri.userInfo.isNotEmpty) return LinkOpenMode.external;
    return trusted.contains(host) ? LinkOpenMode.inApp : LinkOpenMode.external;
  }
}
