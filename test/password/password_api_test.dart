import 'dart:convert';
import 'dart:typed_data';

import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/api/api_messages.dart';
import 'package:connectum/data/repositories/auth_repository.dart';
import 'package:connectum/data/repositories/session_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Step {
  const _Step(this.status, this.body, {this.json = true});
  final int status;
  final String body;
  final bool json;
}

class _Script implements HttpClientAdapter {
  _Script(this.steps);
  final List<_Step> steps;
  final paths = <String>[];
  final bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    bodies.add(jsonEncode(options.data));
    final step = steps[paths.length <= steps.length ? paths.length - 1 : 0];
    return ResponseBody.fromString(
      step.body,
      step.status,
      headers: {
        Headers.contentTypeHeader: [
          step.json ? Headers.jsonContentType : 'text/plain',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Store extends Fake implements SessionStore {
  _Store({this.sessionToken});
  final String? sessionToken;
  @override
  String? get token => sessionToken;
  @override
  Future<String> deviceId() async => 'dev-1';
}

class _Sessions extends Fake implements SessionRepository {}

String _err(String code, [String message = '']) =>
    '{"ok":false,"error":{"code":"$code","message":"$message"}}';

({AuthRepository auth, _Script script, ApiClient api}) _make(
  List<_Step> steps, {
  String? sessionToken,
}) {
  final script = _Script(steps);
  final store = _Store(sessionToken: sessionToken);
  final api = ApiClient(
    store,
    dio: Dio(BaseOptions(baseUrl: 'http://dev.test/api/sd'))
      ..httpClientAdapter = script,
    retryDelays: const [],
  );
  return (
    auth: AuthRepository(api, store, _Sessions()),
    script: script,
    api: api,
  );
}

Future<ApiException> _resetFails(_Step step) async {
  final m = _make([step]);
  try {
    await m.auth.passwordReset('a@b.co', '123456', 'new password 1');
  } on ApiException catch (e) {
    return e;
  }
  fail('reset should have failed');
}

void main() {
  test(
    'check sends the password exactly as typed and reads {ok:true}',
    () async {
      final m = _make([const _Step(200, '{"ok":true,"data":{"ok":true}}')]);
      final result = await m.auth.passwordCheck('  Pässword 1  ');
      expect(result.isOk, isTrue);
      expect(m.script.paths.single, '/password/check');
      expect(jsonDecode(m.script.bodies.single), {
        'password': '  Pässword 1  ',
      });
    },
  );

  test('check: 400 invalid gives the server words', () async {
    final m = _make([
      _Step(
        400,
        _err('invalid', 'Choose a password of at least 8 characters.'),
      ),
    ]);
    final result = await m.auth.passwordCheck('short');
    expect(result.isOk, isFalse);
    expect(result.message, 'Choose a password of at least 8 characters.');
  });

  test('forgot posts the email and shows nothing about the account', () async {
    final m = _make([const _Step(200, '{"ok":true,"data":{"sent":true}}')]);
    await m.auth.passwordForgot('a@b.co');
    expect(m.script.paths.single, '/password/forgot');
    expect(ApiMessages.passwordForgotSent, contains('If an account'));
  });

  test(
    'reset sends email, code, password as typed and the device id',
    () async {
      final m = _make([_Step(400, _err('invalid'))]);
      await expectLater(
        m.auth.passwordReset('a@b.co', '123456', ' new pass 1 '),
        throwsA(isA<ApiException>()),
      );
      expect(jsonDecode(m.script.bodies.single), {
        'email': 'a@b.co',
        'otp': '123456',
        'newPassword': ' new pass 1 ',
        'deviceId': 'dev-1',
      });
    },
  );

  test('reset 401 otp_invalid: one wording', () async {
    final e = await _resetFails(
      _Step(401, _err('otp_invalid', 'long server text')),
    );
    expect(
      ApiMessages.ofPasswordChange(e),
      "That code isn't valid. Request a new one.",
    );
  });

  test('reset 400 invalid: stronger password', () async {
    final e = await _resetFails(_Step(400, _err('invalid', 'too short')));
    expect(
      ApiMessages.ofPasswordChange(e),
      'Choose a stronger password (8–128 characters).',
    );
  });

  test('reset 400 password_reused', () async {
    final e = await _resetFails(_Step(400, _err('password_reused')));
    expect(
      ApiMessages.ofPasswordChange(e),
      "You can't reuse a recent password.",
    );
  });

  test('reset 503 password_history_unavailable', () async {
    final e = await _resetFails(
      _Step(503, _err('password_history_unavailable', 'x')),
    );
    expect(ApiMessages.ofPasswordChange(e), 'Try again in a minute.');
  });

  test('reset 429 as plain text does not crash', () async {
    final e = await _resetFails(
      const _Step(429, 'Too Many Requests', json: false),
    );
    expect(
      ApiMessages.ofPasswordChange(e),
      'Too many tries. Please wait a minute and try again.',
    );
  });

  test('reset 429 as JSON', () async {
    final e = await _resetFails(_Step(429, _err('rate_limited')));
    expect(
      ApiMessages.ofPasswordChange(e),
      'Too many tries. Please wait a minute and try again.',
    );
  });

  test('any non-JSON error body is a plain error, not a crash', () async {
    for (final status in [400, 401, 500, 502]) {
      final e = await _resetFails(_Step(status, '<html>x</html>', json: false));
      expect(e.status, status);
      expect(ApiMessages.ofPasswordChange(e), isNotEmpty);
    }
  });

  test(
    'a wrong code (401 otp_invalid) never signs a signed-in session out',
    () async {
      final m = _make([_Step(401, _err('otp_invalid'))], sessionToken: 'tok');
      var fired = 0;
      m.api.unauthorized.listen((_) => fired++);
      await expectLater(
        m.auth.passwordReset('a@b.co', '1', 'x'),
        throwsA(isA<ApiException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fired, 0);
    },
  );

  test('a 401 on a session call tells the app to go to Sign In', () async {
    for (final body in [_err('unauthenticated'), 'Unauthorized']) {
      final m = _make([
        _Step(401, body, json: body.startsWith('{')),
      ], sessionToken: 'tok');
      var fired = 0;
      m.api.unauthorized.listen((_) => fired++);
      await expectLater(m.api.get('/session'), throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      expect(fired, 1, reason: body);
    }
  });
}
