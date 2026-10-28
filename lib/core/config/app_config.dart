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

  static void validate() {
    if (!kReleaseMode) return;
    final isSecure =
        Uri.tryParse(baseUrl)?.scheme == 'https' &&
        Uri.tryParse(wsUrl)?.scheme == 'wss';
    if (!isSecure) {
      throw StateError('Release builds need https BASE_URL and wss WS_URL.');
    }
  }
}
