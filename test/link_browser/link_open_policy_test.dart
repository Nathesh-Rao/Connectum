import 'package:connectum/core/utils/link_open_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const trusted = {'connectum.app', 'erp.acme.com'};
  const cleartext = {'10.0.2.113'};
  LinkOpenMode d(String u) =>
      LinkOpenPolicy.decide(u, trusted, cleartextHosts: cleartext);

  final table = <String, LinkOpenMode>{
    'https://connectum.app/page': LinkOpenMode.inApp,
    'https://erp.acme.com/x?a=1#f': LinkOpenMode.inApp,
    'https://CONNECTUM.App/page': LinkOpenMode.inApp,
    'https://connectum.app:8443/p': LinkOpenMode.inApp,
    'https://connectum.app./p': LinkOpenMode.inApp,
    'HTTPS://connectum.app/p': LinkOpenMode.inApp,
    'https://example.org': LinkOpenMode.external,
    'https://accounts.google.com/o': LinkOpenMode.external,
    'https://trusted.com.evil.com/': LinkOpenMode.external,
    'https://connectum.app.evil.com/': LinkOpenMode.external,
    'https://evilconnectum.app/': LinkOpenMode.external,
    'https://sub.connectum.app/': LinkOpenMode.external,
    'https://connectum.app@evil.com/': LinkOpenMode.external,
    'https://connectum.app:pw@connectum.app/': LinkOpenMode.external,
    'https://evil.com/@connectum.app': LinkOpenMode.external,
    'https://evil.com#@connectum.app': LinkOpenMode.external,
    'http://example.org': LinkOpenMode.blocked,
    'http://connectum.app': LinkOpenMode.blocked,
    'http://10.0.2.113:8080/x': LinkOpenMode.external,
    'mailto:a@b.com': LinkOpenMode.external,
    'tel:+911234': LinkOpenMode.external,
    'sms:+911234': LinkOpenMode.external,
    'javascript:alert(1)': LinkOpenMode.blocked,
    'file:///etc/passwd': LinkOpenMode.blocked,
    'intent://x#Intent;scheme=https;end': LinkOpenMode.blocked,
    'data:text/html,hi': LinkOpenMode.blocked,
    'myapp://open': LinkOpenMode.blocked,
    'ftp://connectum.app/x': LinkOpenMode.blocked,
    'https:///nohost': LinkOpenMode.blocked,
    '/relative/path': LinkOpenMode.blocked,
    '': LinkOpenMode.blocked,
    '   https://connectum.app/p  ': LinkOpenMode.inApp,
  };

  for (final e in table.entries) {
    test('"${e.key}" -> ${e.value.name}', () => expect(d(e.key), e.value));
  }

  test('trusted hosts are matched ignoring case and a trailing dot', () {
    expect(LinkOpenPolicy.decide('https://a.b/', {'A.B.'}), LinkOpenMode.inApp);
  });
}
