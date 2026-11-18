import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/api/api_client.dart';
import '../../data/socket/socket_service.dart';
import 'crash_sanitizer.dart';

const _expectedCodes = {
  'stale',
  'forbidden',
  'not_found',
  'invalid',
  'invalid_values',
  'bad_request',
  'busy',
  'rate_limited',
  'otp_invalid',
  'password_history_unavailable',
  'session_expired',
  'session_ended',
  'unauthenticated',
};

const _expectedStatuses = {401, 403, 404, 409, 429};

const _expectedWords = [
  'session_expired',
  'session_ended',
  'socketexception',
  'handshakeexception',
  'tlsexception',
  'timeoutexception',
  'no network',
  'offline',
  'cancelled',
  'canceled',
];

/// True for errors the app answers with a normal message (server refusals,
/// no network, timeouts, cancellations): never reported.
bool isExpectedError(Object error) {
  if (error is ApiException) {
    return _expectedCodes.contains(error.code) ||
        _expectedStatuses.contains(error.status) ||
        (error.code == 'network' && error.status == null);
  }
  if (error is SocketCallError) {
    return _expectedCodes.contains(error.code) || error.isConnectionGap;
  }
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.transformTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.connectionError ||
          DioExceptionType.cancel ||
          DioExceptionType.badCertificate:
        return true;
      case DioExceptionType.badResponse:
        return _expectedStatuses.contains(error.response?.statusCode);
      case DioExceptionType.unknown:
        final inner = error.error;
        return inner is SocketException ||
            inner is HandshakeException ||
            inner is TlsException ||
            inner is TimeoutException;
    }
  }
  if (error is SocketException ||
      error is HandshakeException ||
      error is TlsException ||
      error is TimeoutException ||
      error is WebSocketChannelException) {
    return true;
  }
  final text = error.toString().toLowerCase();
  return _expectedWords.any(text.contains);
}

/// The type and a cleaned message of [error]; raw text of errors that can
/// carry content (a parse error quotes its input, a Dio error its URL) is
/// left out.
SanitizedError sanitizeError(Object error) {
  final type = error.runtimeType.toString();
  if (error is DioException) {
    return SanitizedError(
      type,
      '${error.type.name} ${error.response?.statusCode ?? ''}'.trim(),
    );
  }
  if (error is FormatException) return SanitizedError(type, '');
  if (error is SanitizedError) return error;
  return SanitizedError(type, CrashSanitizer.clean(error.toString()));
}
