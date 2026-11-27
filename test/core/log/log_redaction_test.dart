import 'dart:convert';
import 'dart:typed_data';

import 'package:connectum/core/log/log_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _decode(String s) => jsonDecode(s) as Map<String, dynamic>;

void main() {
  const keys = [
    'password',
    'passwd',
    'pwd',
    'pin',
    'otp',
    'code',
    'otpCode',
    'verificationId',
    'token',
    'accessToken',
    'refreshToken',
    'idToken',
    'secret',
    'apiKey',
    'api_key',
    'authorization',
    'cookie',
    'set-cookie',
    'session',
    'sid',
    'privateKey',
    'publicKey',
    'key',
    'recovery',
    'recoveryCode',
    'mnemonic',
    'signature',
    'jwt',
    'credential',
    'deviceKey',
    'wrappedKey',
    'wrapped_dek',
    'salt',
  ];

  group('secret keys', () {
    for (final k in keys) {
      for (final variant in [k, k.toUpperCase()]) {
        test('$variant top level and nested', () {
          final out = _decode(
            LogRedaction.body('x.y', {
              variant: 'v1',
              'list': [
                {
                  'deep': {variant: 'v2'},
                },
              ],
              'name': 'Ticket',
            }),
          );
          expect(out[variant], '***');
          expect(out['list'][0]['deep'][variant], '***');
          expect(out['name'], 'Ticket');
        });
      }
    }

    test('JSON inside a string is decoded and masked', () {
      final out = _decode(
        LogRedaction.body('x.y', {'payload': '{"password":"hunter2","a":1}'}),
      );
      expect(out['payload'], {'password': '***', 'a': 1});
    });

    test('the example request leaves only the name', () {
      final s = LogRedaction.body('tstruct.submit', {
        'password': 'hunter2',
        'otp': '123456',
        'token': 'abc',
        'name': 'Ticket',
      });
      expect(_decode(s), {
        'password': '***',
        'otp': '***',
        'token': '***',
        'name': 'Ticket',
      });
      for (final leak in ['hunter2', '123456', '"abc"']) {
        expect(s, isNot(contains(leak)));
      }
    });
  });

  group('sensitive actions', () {
    for (final a in [
      'e2e.register',
      'e2e.sync.put',
      'POST /login/verify',
      'POST /password/reset',
      'POST /login/start',
      'session.current',
      'POST /enter',
    ]) {
      test('$a is fully redacted both ways', () {
        expect(
          LogRedaction.body(a, {'name': 'x'}),
          LogRedaction.redactedAction,
        );
        expect(
          LogRedaction.body(a, {'ok': 1}, isFailure: true),
          LogRedaction.redactedAction,
        );
      });
    }
    test('an ordinary action is not', () {
      expect(LogRedaction.isSensitiveAction('tstruct.submit'), isFalse);
      expect(LogRedaction.isSensitiveAction('GET /me'), isFalse);
    });
  });

  group('content', () {
    test('message text and file names are masked', () {
      final out = _decode(
        LogRedaction.body('conv.send', {
          'text': 'hello',
          'comment': 'abc',
          'fileName': 'cv.pdf',
          'id': 3,
        }),
      );
      expect(out, {
        'text': '<text 5 chars>',
        'comment': '<text 3 chars>',
        'fileName': '<name masked>',
        'id': 3,
      });
    });

    test('form captions are logged outside chat actions, masked inside', () {
      const data = {'caption': 'Leave Request', 'id': 'leave-request'};
      expect(jsonDecode(LogRedaction.body('options.list', data)), {
        'caption': 'Leave Request',
        'id': 'leave-request',
      });
      expect(
        jsonDecode(
          LogRedaction.body('record.send', {'text': 'hi', 'caption': 'abc'}),
        ),
        {'text': '<text 2 chars>', 'caption': '<text 3 chars>'},
      );
    });

    test('a non-JSON request is masked as text', () {
      expect(
        LogRedaction.body('#tstruct', '#tstruct leave'),
        '<text 14 chars>',
      );
    });

    test('long strings and binary bodies', () {
      final out = _decode(
        LogRedaction.body('x', {'blob': 'a' * 201, 'ok': 'a' * 200}),
      );
      expect(out['blob'], '<201 chars>');
      expect(out['ok'], 'a' * 200);
      expect(
        LogRedaction.body('x', Uint8List(500)),
        '<file upload 500 bytes, name masked>',
      );
    });

    test('lists over 20 items show 3', () {
      final out =
          jsonDecode(LogRedaction.body('x', List.generate(25, (i) => i)))
              as List;
      expect(out, [0, 1, 2, '(+22 more items)']);
      final twenty =
          jsonDecode(LogRedaction.body('x', List.generate(20, (i) => i)))
              as List;
      expect(twenty, hasLength(20));
    });

    test('2 KB and 8 KB caps', () {
      final ok = LogRedaction.body('x', {
        for (var i = 0; i < 400; i++) 'k$i': 'value$i',
      });
      expect(ok.length, lessThan(2048 + 30));
      expect(ok, contains('...(+'));
      final bad = LogRedaction.body('x', {
        for (var i = 0; i < 2000; i++) 'k$i': 'value$i',
      }, isFailure: true);
      expect(bad.length, inInclusiveRange(8192, 8192 + 30));
    });

    test('headers allowlist', () {
      expect(
        LogRedaction.headers({
          'Content-Type': 'json',
          'Authorization': 'Bearer abc',
          'Cookie': 'a=b',
          'x-request-id': '7',
          'status': 200,
        }),
        {'Content-Type': 'json', 'x-request-id': '7', 'status': '200'},
      );
    });

    test('a redaction failure never leaks the raw body', () {
      final out = LogRedaction.body('x', _Boom());
      expect(out, LogRedaction.errorText);
      expect(out, isNot(contains('secret-raw')));
    });
  });
}

class _Boom implements Map<String, dynamic> {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('secret-raw');
}
