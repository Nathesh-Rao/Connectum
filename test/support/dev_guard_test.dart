import 'package:flutter_test/flutter_test.dart';

import 'dev_guard.dart';

Future<String> _body(String env) async =>
    '{"ok":true,"data":{"release":"abc1234","node":"n","environment":"$env"}}';

void main() {
  const base = 'http://10.0.2.113';

  test('passes on dev and the allowed host', () async {
    await DevGuard.assertDevOnly(
      base,
      allowedHost: '10.0.2.113',
      fetch: (_) => _body('dev'),
    );
  });

  test('throws when the environment is not dev', () {
    expect(
      DevGuard.assertDevOnly(
        base,
        allowedHost: '10.0.2.113',
        fetch: (_) => _body('production'),
      ),
      throwsStateError,
    );
  });

  test('throws on a host that is not the allowed one', () {
    expect(
      DevGuard.assertDevOnly(
        'https://connectum.app',
        allowedHost: '10.0.2.113',
        fetch: (_) => _body('dev'),
      ),
      throwsStateError,
    );
  });

  test('throws when the server cannot be read', () {
    expect(
      DevGuard.assertDevOnly(
        base,
        allowedHost: '10.0.2.113',
        fetch: (_) async => throw Exception('down'),
      ),
      throwsStateError,
    );
  });
}
