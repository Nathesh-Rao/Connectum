import 'dart:convert';
import 'dart:io';

/// Every integration test calls `DevGuard.assertDevOnly(baseUrl)` first.
/// It throws unless the server says `environment: dev` AND the host is the
/// one named in the `DEV_HOST` environment variable (set it to the dev
/// machine's address, e.g. `DEV_HOST=10.0.2.113`). Production is never used.
class DevGuard {
  DevGuard._();

  /// `fetch` replaces the real HTTP call in unit tests of the guard.
  static Future<void> assertDevOnly(
    String baseUrl, {
    String? allowedHost,
    Future<String> Function(Uri url)? fetch,
  }) async {
    final allowed = allowedHost ?? Platform.environment['DEV_HOST'] ?? '';
    if (allowed.isEmpty) {
      throw StateError('DevGuard: set DEV_HOST to the allowed dev host.');
    }
    final base = Uri.parse(baseUrl);
    if (base.host != allowed) {
      throw StateError(
        'DevGuard: ${base.host} is not the allowed dev host ($allowed).',
      );
    }
    final url = Uri.parse(
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/sd/version',
    );
    final Object? body;
    try {
      body = jsonDecode(await (fetch ?? _get)(url));
    } catch (e) {
      throw StateError('DevGuard: could not read $url ($e).');
    }
    final data = body is Map ? body['data'] : null;
    final environment = data is Map ? data['environment'] : null;
    if (environment != 'dev') {
      throw StateError(
        'DevGuard: $url says environment "$environment", not "dev". '
        'Refusing to run.',
      );
    }
  }

  static Future<String> _get(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      return await utf8.decodeStream(response);
    } finally {
      client.close(force: true);
    }
  }
}
