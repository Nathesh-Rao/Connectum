import 'package:connectum/core/log/log_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime(2026, 11, 23, 17, 34, 12, 345);

  final lead = '10:10:06.785  I  ';
  const pad = '                           '; // 27 spaces

  String e({
    String level = 'I',
    String tag = 'app',
    required String message,
    String? caller,
    List<String> details = const [],
    int repeat = 1,
  }) => LogFormatter.entry(
    at: DateTime(2026, 11, 24, 10, 10, 6, 785),
    level: level,
    tag: tag,
    message: message,
    caller: caller,
    details: details,
    repeat: repeat,
  );

  group('entry blocks', () {
    final cases = <String, (String, String)>{
      'I line': (
        e(message: 'main() started'),
        '${lead}APP       main() started\n',
      ),
      'W with repeat': (
        e(
          level: 'W',
          tag: 'app_database',
          message: 'migration check slow (412 ms)',
          repeat: 4,
        ),
        '10:10:06.785  W  DB        migration check slow (412 ms)  (x4)\n',
      ),
      'single occurrence has no suffix': (
        e(message: 'x', repeat: 1),
        '${lead}APP       x\n',
      ),
      'suffix for three': (
        e(message: 'x', repeat: 3),
        '${lead}APP       x  (x3)\n',
      ),
      'E with caller and stack': (
        e(
          level: 'E',
          tag: 'flutter_error',
          message: "TypeError: type 'Null' is not a subtype of type 'String'",
          caller: 'SubmissionRepository.flush (submission_repository.dart:736)',
          details: ['#0 a (package:connectum/a.dart:1:1)'],
        ),
        "10:10:06.785  E  ERROR     TypeError: type 'Null' is not a subtype of type\n"
            "$pad'String'\n"
            '${pad}at SubmissionRepository.flush (submission_repository.dart:736)\n'
            '$pad#0 a (package:connectum/a.dart:1:1)\n',
      ),
      'API request': (
        e(
          tag: 'API #2',
          message: 'options.list  ->  request\n{"module":"forms"}',
        ),
        '10:10:06.785  I  API #2    options.list  ->  request\n'
            '$pad{"module":"forms"}\n',
      ),
      'unknown tag uppercased and cut to 8': (
        e(tag: 'some_long_tag', message: 'm'),
        '${lead}SOME_LON  m\n',
      ),
    };
    cases.forEach((name, c) => test(name, () => expect(c.$1, c.$2)));
  });

  test('wraps at 80 columns with a hanging indent, never inside a word', () {
    final out = e(
      message: List.filled(20, 'word').join(' '),
    ).trimRight().split('\n');
    expect(out.length, greaterThan(1));
    for (final l in out) {
      expect(l.length, lessThanOrEqualTo(80));
    }
    expect(out[1], startsWith(pad));
    expect(out[1].trim(), startsWith('word'));
    final long = 'x' * 100;
    expect(e(message: long).trimRight(), '${lead}APP       $long');
  });

  test('date line is padded to 80 with dashes', () {
    final l = LogFormatter.dateLine(DateTime(2026, 11, 24));
    expect(l, '-- 2026-11-24 ${'-' * 66}\n');
    expect(l.trimRight().length, 80);
  });

  test('session block is boxed', () {
    final b = LogFormatter.sessionBlock(
      DateTime(2026, 11, 24, 10, 10, 6, 742),
      '1.5.0 (7)',
    );
    expect(
      b,
      '${'=' * 80}\nSESSION START   2026-11-24 10:10:06.742    app 1.5.0 (7)\n'
      '${'=' * 80}\n-- 2026-11-24 ${'-' * 66}\n',
    );
  });

  group('body lines', () {
    test('short JSON stays compact', () {
      expect(LogFormatter.bodyLines('{"module":"forms"}'), [
        '{"module":"forms"}',
      ]);
    });

    test('long JSON is pretty with 2-space indent', () {
      final body =
          '{"data":[{"caption":"Leave Request","id":"leave-request"},{"id":222222}]}';
      expect(body.length, greaterThan(70));
      expect(LogFormatter.bodyLines(body), [
        '{',
        '  "data": [',
        '    {',
        '      "caption": "Leave Request",',
        '      "id": "leave-request"',
        '    },',
        '    {',
        '      "id": 222222',
        '    }',
        '  ]',
        '}',
      ]);
    });

    test('arrays over 3 items are cut with the more-items text', () {
      final out = LogFormatter.bodyLines(
        '{"a":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18],"pad":"${'p' * 60}"}',
      );
      expect(out, contains('    ... (+15 more items)'));
      expect(out.where((l) => l.trim() == '4,' || l.trim() == '4'), isEmpty);
    });

    test('redaction marker is folded into the count', () {
      final out = LogFormatter.bodyLines(
        '{"a":[1,2,3,"(+17 more items)"],"pad":"${'p' * 60}"}',
      );
      expect(out, contains('    ... (+17 more items)'));
    });

    test('over 40 pretty lines falls back to compact, wrapped on commas', () {
      final body = '{${[for (var i = 0; i < 45; i++) '"k$i":1'].join(',')}}';
      final out = LogFormatter.bodyLines(body);
      expect(out.length, lessThan(45));
      for (final l in out) {
        expect(l.length, lessThanOrEqualTo(LogFormatter.messageWidth));
      }
      expect(out.join(), body);
    });

    test('truncated JSON is kept as text', () {
      expect(
        LogFormatter.bodyLines('{"a":1...(+5 chars)').join(),
        contains('(+5 chars)'),
      );
    });
  });

  test('caller is the first app frame outside core/log', () {
    final stack = StackTrace.fromString(
      '#0      AppLog.e (package:connectum/core/log/app_log.dart:20:5)\n'
      '#1      Foo._bar (package:connectum/data/foo.dart:42:9)\n'
      '#2      main (package:connectum/main.dart:1:1)\n',
    );
    expect(LogFormatter.caller(stack), 'Foo._bar (foo.dart:42)');
    expect(
      LogFormatter.caller(StackTrace.fromString('#0 x (dart:core:1:1)')),
      isNull,
    );
  });

  test('frames keeps the first eight', () {
    final stack = StackTrace.fromString(
      [
        for (var i = 0; i < 12; i++) '#$i f$i (package:connectum/a.dart:$i:1)',
      ].join('\n'),
    );
    expect(LogFormatter.frames(stack), hasLength(8));
  });

  test('file name, timestamp and offset', () {
    expect(LogFormatter.fileName(at), 'ConnectumMobileLog_20261123_173412.txt');
    expect(LogFormatter.timestamp(at), '2026-11-23 17:34:12.345');
    expect(
      LogFormatter.withOffset(at),
      matches(r'^2026-11-23 17:34:12 [+-]\d\d:\d\d$'),
    );
  });

  test('header lists the labels, unknown context and an 80 char rule', () {
    final h = LogFormatter.header(
      env: const LogEnvironment(
        version: '1.0.0 (7)',
        device: 'Pixel, Android 14',
      ),
      fileCreated: 'c',
      started: at,
      context: LogContext.unknown,
      isAppend: false,
    );
    expect(h, contains('App name:     Connectum Mobile'));
    expect(h, contains('App version:  1.0.0 (7)'));
    expect(h, contains('User:         unknown'));
    expect(h, contains('Organisation: unknown'));
    expect(h, contains('Device:       Pixel, Android 14'));
    expect(h, contains('API bodies:   logged, secrets masked'));
    expect(h.trimRight().split('\n').last, LogFormatter.legend);
    expect(h, contains('\n${'=' * 80}\n'));
  });

  test('context labels: signed in, signed out, unknown', () {
    expect(
      const LogContext(user: 'A <a@b.c>', org: 'Acme', isKnown: true).userLabel,
      'A <a@b.c>',
    );
    expect(const LogContext(isKnown: true).userLabel, 'not signed in');
    expect(const LogContext(isKnown: true).orgLabel, 'unknown');
    expect(LogContext.unknown.userLabel, 'unknown');
  });
}
