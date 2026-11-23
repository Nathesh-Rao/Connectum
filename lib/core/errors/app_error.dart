import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/api/api_client.dart';
import '../../data/socket/call_problem.dart';
import '../../data/socket/socket_service.dart';

enum ErrorKind {
  network,
  offline,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  invalid,
  conflict,
  server,
  parse,
  storage,
  permission,
  cancelled,
  unknown,
}

class AppError implements Exception {
  const AppError(
    this.kind,
    this.message, {
    this.isRetryable = false,
    this.code,
    this.cause,
    this.stack,
  });

  static const offlineText = CallProblem.offlineText;
  static const timeoutText = CallProblem.unknownOutcomeText;
  static const networkText = "Couldn't reach the server. Try again.";
  static const serverText = 'Something went wrong on our side. Try again.';
  static const busyText = 'Too many requests. Wait a moment and try again.';
  static const unauthorizedText = 'Your session has ended. Sign in again.';
  static const forbiddenText = "You can't do that.";
  static const notFoundText = 'That no longer exists.';
  static const invalidText = 'Check the details and try again.';
  static const conflictText = 'That changed meanwhile. Refresh and try again.';
  static const parseText = "Couldn't read the data. Try again.";
  static const storageText = "Couldn't save on this device. Try again.";
  static const permissionText = 'Permission is needed to do that.';
  static const cancelledText = 'Cancelled.';
  static const unknownText = CallProblem.fallbackText;

  final ErrorKind kind;

  /// User-safe text; never raw exception text. A server's own `error.message`
  /// is used only where [CallProblem] already shows it.
  final String message;
  final bool isRetryable;

  /// Server code, for logic only.
  final String? code;

  /// Never shown, never logged raw.
  final Object? cause;
  final StackTrace? stack;

  /// [isWrite]: a timeout or a drop after sending may still have been done.
  factory AppError.from(Object e, {bool isWrite = false, StackTrace? stack}) {
    if (e is AppError) return e;
    if (e is SocketCallError) return _fromCall(e, isWrite, stack);
    if (e is ApiException) return _fromApi(e, stack);
    if (e is DioException) return _fromDio(e, stack);
    if (e is TimeoutException) {
      return AppError(
        ErrorKind.timeout,
        isWrite ? timeoutText : networkText,
        isRetryable: !isWrite,
        cause: e,
        stack: stack,
      );
    }
    if (e is SocketException ||
        e is HandshakeException ||
        e is TlsException ||
        e is WebSocketChannelException) {
      return AppError(
        ErrorKind.network,
        networkText,
        isRetryable: true,
        cause: e,
        stack: stack,
      );
    }
    if (e is FormatException || e is TypeError) {
      return AppError(ErrorKind.parse, parseText, cause: e, stack: stack);
    }
    if (e is DatabaseException || e is FileSystemException) {
      return AppError(ErrorKind.storage, storageText, cause: e, stack: stack);
    }
    if (e is PlatformException) {
      final isPermission = RegExp(
        'permission|denied',
        caseSensitive: false,
      ).hasMatch(e.code);
      return AppError(
        isPermission ? ErrorKind.permission : ErrorKind.unknown,
        isPermission ? permissionText : unknownText,
        code: e.code,
        cause: e,
        stack: stack,
      );
    }
    return AppError(ErrorKind.unknown, unknownText, cause: e, stack: stack);
  }

  static AppError _fromCall(SocketCallError e, bool isWrite, StackTrace? s) {
    final p = CallProblem.of(e, isWrite: isWrite);
    final kind = switch (p.kind) {
      CallProblemKind.offline => ErrorKind.offline,
      CallProblemKind.unknownOutcome => ErrorKind.timeout,
      CallProblemKind.rateLimited || CallProblemKind.busy => ErrorKind.server,
      CallProblemKind.notFound => ErrorKind.notFound,
      CallProblemKind.forbidden => ErrorKind.forbidden,
      CallProblemKind.alreadyResolved ||
      CallProblemKind.stale ||
      CallProblemKind.duplicate => ErrorKind.conflict,
      CallProblemKind.invalid => ErrorKind.invalid,
      CallProblemKind.other => switch (e.code) {
        'invalid_values' => ErrorKind.invalid,
        'in_progress' => ErrorKind.server,
        'submission_locked' => ErrorKind.conflict,
        'unauthenticated' ||
        'session_expired' ||
        'session_ended' => ErrorKind.unauthorized,
        _ => ErrorKind.unknown,
      },
    };
    final isRetryable = p.canRetry || e.code == 'in_progress';
    return AppError(
      kind,
      p.text,
      isRetryable: isRetryable,
      code: e.code,
      cause: e,
      stack: s,
    );
  }

  static AppError _fromApi(ApiException e, StackTrace? s) {
    final status = e.status;
    ErrorKind kind;
    String text;
    var isRetryable = false;
    if (e.code == 'rate_limited' || status == 429) {
      kind = ErrorKind.server;
      text = busyText;
      isRetryable = true;
    } else if (e.isUnauthorized) {
      kind = ErrorKind.unauthorized;
      text = unauthorizedText;
    } else if (status == 403) {
      kind = ErrorKind.forbidden;
      text = forbiddenText;
    } else if (status == 404) {
      kind = ErrorKind.notFound;
      text = notFoundText;
    } else if (e.code == 'network' && status == null) {
      kind = ErrorKind.network;
      text = networkText;
      isRetryable = true;
    } else if (e.code == 'bad_response') {
      kind = ErrorKind.server;
      text = serverText;
    } else if (e.code == 'invalid_values' || e.code == 'invalid') {
      kind = ErrorKind.invalid;
      text = e.message.isEmpty ? invalidText : e.message;
    } else if (status == 409) {
      kind = ErrorKind.conflict;
      text = conflictText;
    } else if (status != null && status >= 500) {
      kind = ErrorKind.server;
      text = serverText;
      isRetryable = true;
    } else {
      kind = ErrorKind.unknown;
      text = unknownText;
    }
    return AppError(
      kind,
      text,
      isRetryable: isRetryable,
      code: e.code,
      cause: e,
      stack: s,
    );
  }

  static AppError _fromDio(DioException e, StackTrace? s) {
    switch (e.type) {
      case DioExceptionType.cancel:
        return AppError(ErrorKind.cancelled, cancelledText, cause: e, stack: s);
      case DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout:
        return AppError(
          ErrorKind.timeout,
          networkText,
          isRetryable: true,
          cause: e,
          stack: s,
        );
      default:
        return AppError(
          ErrorKind.network,
          networkText,
          isRetryable: true,
          cause: e,
          stack: s,
        );
    }
  }

  /// Safe to log: the kind and the server code only.
  @override
  String toString() => 'AppError(${kind.name}${code == null ? '' : ', $code'})';
}
