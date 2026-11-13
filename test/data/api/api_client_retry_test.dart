import 'dart:io';
import 'dart:typed_data';

import 'package:connectum/core/config/app_config.dart';
import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/api/api_messages.dart';
import 'package:connectum/data/session_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers from a script, one entry per call: a status code or a thrown
/// connection error.
class _Script implements HttpClientAdapter {
  _Script(this.steps);

  final List<Object> steps;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final step = steps[calls < steps.length ? calls : steps.length - 1];
    calls++;
    if (step is DioException) {
      throw DioException(
        requestOptions: options,
        type: step.type,
        error: step.error,
      );
    }
    final status = step as int;
    final body = status == 200
        ? '{"ok":true,"data":{"x":1}}'
        : '<html>$status</html>';
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [
          status == 200 ? Headers.jsonContentType : 'text/html',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DioException get _reset => DioException(
  requestOptions: RequestOptions(),
  type: DioExceptionType.connectionError,
  error: const SocketException('Connection reset by peer'),
);

ApiClient _client(_Script script) => ApiClient(
  SessionStore(),
  dio: Dio(BaseOptions(baseUrl: 'http://dev.test/api/sd'))
    ..httpClientAdapter = script,
  retryDelays: const [Duration(milliseconds: 1), Duration(milliseconds: 1)],
);

void main() {
  test('GET retries 503 twice, then succeeds', () async {
    final script = _Script([503, 503, 200]);
    expect(await _client(script).get('/x'), {'x': 1});
    expect(script.calls, 3);
  });

  test('GET retries a connection reset', () async {
    final script = _Script([_reset, 200]);
    expect(await _client(script).get('/x'), {'x': 1});
    expect(script.calls, 2);
  });

  test('GET gives up after two retries with a clear message', () async {
    final script = _Script([503]);
    await expectLater(
      _client(script).get('/x'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 503)
            .having(
              (e) => ApiMessages.of(e),
              'message',
              contains('restarting'),
            ),
      ),
    );
    expect(script.calls, 3);
  });

  test('a plain POST is never retried', () async {
    final script = _Script([503, 200]);
    await expectLater(
      _client(script).post('/command'),
      throwsA(isA<ApiException>()),
    );
    expect(script.calls, 1);
  });

  test('a sign-in start POST retries', () async {
    final script = _Script([503, 200]);
    final data = await _client(script).post('/login/start', shouldRetry: true);
    expect(data, {'x': 1});
    expect(script.calls, 2);
  });

  test('429 is not retried and says wait a minute', () async {
    final script = _Script([429]);
    await expectLater(
      _client(script).post('/login/start', shouldRetry: true),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'rate_limited')
            .having((e) => ApiMessages.of(e), 'message', contains('a minute')),
      ),
    );
    expect(script.calls, 1);
  });

  group('release guard', () {
    test('release refuses http/ws', () {
      expect(
        AppConfig.validate(
          isRelease: true,
          base: 'http://10.0.2.113',
          ws: 'ws://10.0.2.113/ws',
        ),
        isNotNull,
      );
    });

    test('release accepts https/wss', () {
      expect(
        AppConfig.validate(
          isRelease: true,
          base: 'https://connectum.app',
          ws: 'wss://connectum.app/ws',
        ),
        isNull,
      );
    });

    test('debug and profile accept http/ws', () {
      expect(
        AppConfig.validate(
          isRelease: false,
          base: 'http://10.0.2.113',
          ws: 'ws://10.0.2.113/ws',
        ),
        isNull,
      );
    });
  });
}
