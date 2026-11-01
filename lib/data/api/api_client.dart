import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../session_store.dart';

class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status, this.details});

  final String code;
  final String message;
  final int? status;
  final Object? details;

  /// Per-field messages of an `invalid_values` error, if any.
  Map<String, String> get fieldErrors {
    final fields = details is Map ? (details as Map)['fields'] : null;
    if (fields is! Map) return {};
    return {for (final e in fields.entries) '${e.key}': '${e.value}'};
  }

  /// Seconds from the `Retry-After` header of a rate-limited answer.
  int? get retryAfterSeconds =>
      details is Map ? (details as Map)['retryAfter'] as int? : null;

  bool get isUnauthorized => status == 401 || code == 'unauthenticated';

  @override
  String toString() => 'ApiException($code, $status)';
}

class ApiClient {
  ApiClient(this._session) {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.isConfigured
            ? AppConfig.apiBase
            : 'http://unconfigured.invalid',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        contentType: Headers.jsonContentType,
      ),
    );
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      if (kDebugMode) {
        client.badCertificateCallback = (_, host, _) =>
            AppConfig.trustedHosts.contains(host);
      }
      return client;
    };
  }

  final SessionStore _session;
  late final Dio _dio;
  final _unauthorized = StreamController<void>.broadcast();

  /// Fires when a call made with the stored session token gets a 401.
  Stream<void> get unauthorized => _unauthorized.stream;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    String? bearer,
  }) => _send('GET', path, query: query, bearer: bearer);

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    String? bearer,
  }) => _send('POST', path, body: body ?? <String, dynamic>{}, bearer: bearer);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    String? bearer,
  }) async {
    final isSessionCall = bearer == null && _session.token != null;
    final token = bearer ?? _session.token;
    try {
      final response = await _dio.request<Object?>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          headers: token == null ? null : {'Authorization': 'Bearer $token'},
        ),
      );
      return _unwrap(response.data, response.statusCode);
    } on DioException catch (e) {
      final data = e.response?.data;
      final status = e.response?.statusCode;
      final retryAfter = int.tryParse(
        e.response?.headers.value('retry-after') ?? '',
      );
      if (data is Map && data['ok'] == false) {
        final error = ApiException(
          '${(data['error'] as Map?)?['code'] ?? 'error'}',
          '${(data['error'] as Map?)?['message'] ?? ''}',
          status: status,
          details:
              (data['error'] as Map?)?['details'] ??
              (retryAfter == null ? null : {'retryAfter': retryAfter}),
        );
        if (isSessionCall && error.isUnauthorized) _unauthorized.add(null);
        throw error;
      }
      if (isSessionCall && status == 401) _unauthorized.add(null);
      if (status == 429) {
        throw ApiException(
          'rate_limited',
          '',
          status: status,
          details: retryAfter == null ? null : {'retryAfter': retryAfter},
        );
      }
      throw ApiException(
        'network',
        e.message ?? 'Network error',
        status: status,
      );
    }
  }

  Map<String, dynamic> _unwrap(Object? data, int? status) {
    if (data is Map && data['ok'] == true) {
      return (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
    }
    throw ApiException('bad_response', 'Unexpected response', status: status);
  }

  Future<Map<String, dynamic>> enter(
    String identityToken,
    String enterprise,
    String deviceId,
  ) => post(
    '/enter',
    body: {'enterprise': enterprise, 'deviceId': deviceId},
    bearer: identityToken,
  );

  Future<Map<String, dynamic>> session() => get('/session');

  Future<void> logout() async {
    await post('/logout');
  }
}
