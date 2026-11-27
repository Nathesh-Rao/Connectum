import 'package:connectum/core/log/api_log.dart';
import 'package:connectum/core/log/log_formatter.dart';
import 'package:connectum/core/log/log_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lines = <String>[];
  var isOn = true;

  setUp(() {
    lines.clear();
    isOn = true;
    ApiLog.isOn = () => isOn;
    ApiLog.write = (level, tag, message) => lines.add(
      LogFormatter.entry(
        at: DateTime(2026, 11, 24, 10, 10, 6, 785),
        level: level,
        tag: tag,
        message: message,
      ).trimRight(),
    );
  });

  test('request and answer share the id and the format', () {
    final call = ApiLog.begin('tstruct.submit', {
      'name': 'Ticket',
      'cid': 'abc',
    })!;
    call.ok({'recordStatus': 'saved'});
    expect(lines, hasLength(2));
    final id = RegExp(r'API #(\d+)').firstMatch(lines[0])!.group(1);
    expect(
      lines[0],
      '10:10:06.785  I  API #$id${' ' * (8 - 'API #$id'.length + 2)}tstruct.submit  ->  request\n'
      '${' ' * 27}{"name":"Ticket","cid":"abc"}',
    );
    expect(
      lines[1],
      matches(
        RegExp(
          r'^10:10:06\.785  I  API #\d+ +tstruct\.submit  <-  OK  \d+ ms\n',
        ),
      ),
    );
    expect(lines[1], contains('{"recordStatus":"saved"}'));
  });

  test('a list answer shows the item count and the caller line', () {
    final call = ApiLog.begin('options.list', {'module': 'forms'})!;
    call.ok({
      'data': [
        for (var i = 0; i < 9; i++) {'caption': 'Form $i', 'id': 'f$i'},
      ],
    });
    expect(lines[1], contains('<-  OK  '));
    expect(lines[1], contains(' ms  (9 items)'));
    expect(lines[1], contains('... (+6 more items)'));
    expect(lines[1], contains('"caption": "Form 0"'));
    expect(lines[1], isNot(contains('<text')));
  });

  test('version answer carries no headers', () {
    ApiLog.begin('GET /version', null)!.ok({'v': 1}, headers: {'status': 200});
    expect(lines[1], isNot(contains('status=200')));
  });

  test('FAILED is level E with code, message and no response is W', () {
    ApiLog.begin('conv.read', {})!.failed('not_found', 'No such conversation.');
    expect(lines[0], contains('  I  '));
    expect(lines[1], contains('  E  '));
    expect(lines[1], contains('<-  FAILED  '));
    expect(lines[1], contains('code=not_found'));
    expect(lines[1], contains('\n${' ' * 27}No such conversation.'));
    ApiLog.begin(
      'conv.read',
      {},
    )!.noResponse('SocketException', 'Connection refused');
    expect(lines[3], contains('  W  '));
    expect(lines[3], contains('<-  NO RESPONSE  '));
    expect(lines[3], contains('Connection refused'));
  });

  test('sensitive action: only the action and the result', () {
    final call = ApiLog.begin('POST /login/verify', {'otp': '123456'})!;
    call.failed('otp_invalid', 'Wrong code 123456');
    expect(lines.join('\n'), isNot(contains('123456')));
    expect(lines[0], contains('<redacted: auth/crypto action>'));
  });

  test('logging OFF builds nothing and never redacts', () {
    isOn = false;
    final before = LogRedaction.calls;
    expect(ApiLog.begin('tstruct.submit', {'password': 'x'}), isNull);
    expect(lines, isEmpty);
    expect(LogRedaction.calls, before);
  });
}
