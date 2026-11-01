import 'package:flutter/foundation.dart';

class AppConfig {
  AppConfig._();

  static const baseUrl = String.fromEnvironment('BASE_URL');
  static const wsUrl = String.fromEnvironment('WS_URL');

  /// Debug only: START_ROUTE=/gallery or /debug/socket opens that screen first.
  static const startRoute = String.fromEnvironment('START_ROUTE');

  static bool get isConfigured => baseUrl.isNotEmpty && wsUrl.isNotEmpty;

  static String get apiBase =>
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/sd';

  static Set<String> get trustedHosts => {
    for (final url in [baseUrl, wsUrl])
      if (url.isNotEmpty) Uri.parse(url).host,
  };

  /// Null when the build is configured; otherwise what is wrong. Debug builds
  /// may run unconfigured or on plain http/ws.
  static String? validate() {
    if (kDebugMode) return null;
    if (baseUrl.isEmpty || wsUrl.isEmpty) {
      return 'BASE_URL and WS_URL were not set for this build.';
    }
    final isSecure =
        Uri.tryParse(baseUrl)?.scheme == 'https' &&
        Uri.tryParse(wsUrl)?.scheme == 'wss';
    return isSecure ? null : 'BASE_URL must be https and WS_URL must be wss.';
  }
}
