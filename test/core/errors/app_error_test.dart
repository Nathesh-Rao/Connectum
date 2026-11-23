import 'dart:async';
import 'dart:io';

import 'package:connectum/core/errors/app_error.dart';
import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:dio/dio.dart';

AppError call(String code, {String msg = '', bool isWrite = false}) =>
    AppError.from(SocketCallError(code, msg), isWrite: isWrite);

void main() {
  group('SocketCallError', () {
    test('not_connected is offline and retryable', () {
      final e = call('not_connected', isWrite: true);
      expect(e.kind, ErrorKind.offline);
      expect(e.isRetryable, isTrue);
      expect(e.message, AppError.offlineText);
    });

    test('timeout and disconnected: offline for reads, timeout for writes', () {
      for (final code in ['timeout', 'disconnected']) {
        expect(call(code).kind, ErrorKind.offline);
        final w = call(code, isWrite: true);
        expect(w.kind, ErrorKind.timeout);
        expect(w.isRetryable, isFalse);
        expect(w.message, AppError.timeoutText);
      }
    });

    test('server codes map to kinds', () {
      expect(call('forbidden').kind, ErrorKind.forbidden);
      expect(call('not_found').kind, ErrorKind.notFound);
      expect(call('invalid').kind, ErrorKind.invalid);
      expect(call('invalid_values').kind, ErrorKind.invalid);
      expect(call('stale').kind, ErrorKind.conflict);
      expect(call('already_resolved').kind, ErrorKind.conflict);
      expect(call('duplicate').kind, ErrorKind.conflict);
      expect(call('submission_locked').kind, ErrorKind.conflict);
      expect(call('session_expired').kind, ErrorKind.unauthorized);
      expect(call('whatever').kind, ErrorKind.unknown);
    });

    test('rate_limited, busy, in_progress are retryable', () {
      for (final code in ['rate_limited', 'busy', 'in_progress']) {
        final e = call(code);
        expect(e.kind, ErrorKind.server, reason: code);
        expect(e.isRetryable, isTrue, reason: code);
      }
    });

    test('keeps the server message, falls back when empty', () {
      expect(call('forbidden', msg: 'Not yours').message, 'Not yours');
      expect(call('whatever').message, AppError.unknownText);
      expect(call('forbidden').code, 'forbidden');
    });
  });

  group('ApiException', () {
    AppError api(String code, {int? status, String msg = ''}) =>
        AppError.from(ApiException(code, msg, status: status));

    test('statuses', () {
      expect(api('x', status: 401).kind, ErrorKind.unauthorized);
      expect(api('x', status: 403).kind, ErrorKind.forbidden);
      expect(api('x', status: 404).kind, ErrorKind.notFound);
      expect(api('x', status: 409).kind, ErrorKind.conflict);
      expect(api('x', status: 429).isRetryable, isTrue);
      expect(api('rate_limited').isRetryable, isTrue);
      expect(api('x', status: 503).isRetryable, isTrue);
    });

    test('network and bad_response', () {
      final n = api('network', msg: 'raw dio text');
      expect(n.kind, ErrorKind.network);
      expect(n.isRetryable, isTrue);
      expect(n.message, isNot(contains('raw')));
      expect(api('bad_response', status: 200).kind, ErrorKind.server);
    });

    test('invalid_values shows the server message', () {
      final e = api('invalid_values', status: 400, msg: 'Name is required');
      expect(e.kind, ErrorKind.invalid);
      expect(e.message, 'Name is required');
    });
  });

  group('exceptions', () {
    test('network family', () {
      for (final e in <Object>[
        const SocketException('secret host'),
        const HandshakeException('x'),
      ]) {
        final a = AppError.from(e);
        expect(a.kind, ErrorKind.network);
        expect(a.isRetryable, isTrue);
        expect(a.message, isNot(contains('secret')));
        expect(a.cause, same(e));
      }
    });

    test('timeout', () {
      expect(AppError.from(TimeoutException('x')).kind, ErrorKind.timeout);
      expect(AppError.from(TimeoutException('x')).isRetryable, isTrue);
      final w = AppError.from(TimeoutException('x'), isWrite: true);
      expect(w.isRetryable, isFalse);
    });

    test('parse', () {
      expect(
        AppError.from(const FormatException('{"a"')).kind,
        ErrorKind.parse,
      );
      expect(AppError.from(TypeError()).kind, ErrorKind.parse);
      expect(
        AppError.from(const FormatException('{"a"')).message,
        AppError.parseText,
      );
    });

    test('storage', () {
      expect(
        AppError.from(const FileSystemException('x')).kind,
        ErrorKind.storage,
      );
      expect(AppError.from(_Db()).kind, ErrorKind.storage);
    });

    test('platform permission', () {
      final p = AppError.from(
        PlatformException(code: 'camera_permission_denied'),
      );
      expect(p.kind, ErrorKind.permission);
      expect(
        AppError.from(PlatformException(code: 'boom')).kind,
        ErrorKind.unknown,
      );
    });

    test('dio', () {
      DioException d(DioExceptionType t) => DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: t,
      );
      expect(
        AppError.from(d(DioExceptionType.cancel)).kind,
        ErrorKind.cancelled,
      );
      expect(
        AppError.from(d(DioExceptionType.receiveTimeout)).kind,
        ErrorKind.timeout,
      );
      expect(
        AppError.from(d(DioExceptionType.connectionError)).kind,
        ErrorKind.network,
      );
    });

    test('unknown, and an AppError passes through', () {
      final u = AppError.from(StateError('x'));
      expect(u.kind, ErrorKind.unknown);
      expect(AppError.from(u), same(u));
    });

    test('toString carries no cause text', () {
      final e = AppError.from(const SocketException('token=abc'));
      expect(e.toString(), isNot(contains('abc')));
    });
  });
}

class _Db implements DatabaseException {
  @override
  dynamic noSuchMethod(Invocation i) => null;
  @override
  String toString() => 'db';
}
