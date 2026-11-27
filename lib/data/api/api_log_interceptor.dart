import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/log/api_log.dart';

/// Logs every REST call of the Dio it is added to, through [ApiLog].
class ApiLogInterceptor extends Interceptor {
  static const _key = 'apiLogCall';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final call = ApiLog.begin(
      '${options.method} ${options.path}',
      options.data,
    );
    if (call != null) options.extra[_key] = call;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final call = response.requestOptions.extra[_key];
    if (call is ApiCall) {
      call.ok(
        response.data,
        headers: {
          'status': response.statusCode,
          'content-type': response.headers.value('content-type'),
          'content-length': response.headers.value('content-length'),
          'x-request-id': response.headers.value('x-request-id'),
        }..removeWhere((_, v) => v == null),
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final call = err.requestOptions.extra[_key];
    if (call is ApiCall) {
      final res = err.response;
      if (res == null) {
        final inner = err.error;
        call.noResponse(
          inner is SocketException ? 'SocketException' : err.type.name,
          inner is SocketException ? inner.message : null,
        );
      } else {
        final data = res.data;
        final error = data is Map ? data['error'] : null;
        call.failed(
          error is Map
              ? '${error['code'] ?? res.statusCode}'
              : '${res.statusCode}',
          error is Map ? '${error['message'] ?? ''}' : '',
          body: error is Map ? error['details'] : data,
        );
      }
    }
    handler.next(err);
  }
}
