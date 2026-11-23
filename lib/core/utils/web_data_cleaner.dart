import 'package:webview_flutter/webview_flutter.dart';

/// Drops what the in-app browser kept (cookies, cache, local storage) so a
/// signed-out phone holds nothing of the last person's web sessions.
class WebDataCleaner {
  WebDataCleaner._();

  static Future<void> clear() async {
    try {
      await WebViewCookieManager().clearCookies();
      final web = WebViewController();
      await web.clearCache();
      await web.clearLocalStorage();
    } catch (_) {
      // Best effort: a sign out never waits on the web view.
    }
  }
}
