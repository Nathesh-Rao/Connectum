import '../../data/repositories/qr_repository.dart';

/// Debug-only sample data for /debug/qr: no server. Each scenario is a
/// `connect.my` answer, so the real parser runs on it. Remove before release
/// (see CLAUDE.md).
class SeedQr {
  SeedQr._();

  static const scenarios = [
    SeedQrScenario('Person and organisation (3 branches)'),
    SeedQrScenario('Organisation without branches', hasBranches: false),
    SeedQrScenario('Very long names', isLong: true),
    SeedQrScenario('Only my QR offered', hasOrganisation: false),
    SeedQrScenario('No public URL (connectum: text)', hasUrl: false),
    SeedQrScenario('Fails once, then loads', failsOnce: true),
  ];
}

class SeedQrScenario {
  const SeedQrScenario(
    this.label, {
    this.hasBranches = true,
    this.isLong = false,
    this.hasOrganisation = true,
    this.hasUrl = true,
    this.failsOnce = false,
  });

  static const _delay = Duration(milliseconds: 600);
  static const _personCode = 'KVZDHDQD';
  static const _orgCode = '7454YKKJ';
  static const _site = 'https://connectum.app/connect';

  final String label;
  final bool hasBranches;
  final bool isLong;
  final bool hasOrganisation;
  final bool hasUrl;
  final bool failsOnce;

  QrRepository repository() {
    var hasFailed = false;
    return QrRepository.from(() async {
      await Future<void>.delayed(_delay);
      if (failsOnce && !hasFailed) {
        hasFailed = true;
        throw Exception('sample failure');
      }
      return answer();
    });
  }

  String _link(String path) => hasUrl ? '$_site/$path' : 'connectum:$path';

  Map<String, dynamic> answer() {
    final org = isLong
        ? 'Greenfield Community Health and Wellbeing Cooperative of South India'
        : 'Sri Ganesh Clinic';
    final personLink = _link('$_personCode?org=$_orgCode');
    final orgLink = _link(_orgCode);
    final branches = isLong
        ? const [
            [
              'North Regional Outpatient and Diagnostics Centre, Annex B',
              'Chennai',
            ],
            ['Chennai Main', null],
            ['Café Zürich', 'Zürich'],
          ]
        : const [
            ['Chennai Main', 'Chennai'],
            ['Coimbatore', 'Coimbatore'],
            ['Madurai', null],
          ];
    return {
      'person': {
        'code': _personCode,
        'display': 'KVZD-HDQD',
        'payload': personLink,
        'url': hasUrl ? personLink : null,
        'name': isLong
            ? 'Dr. Venkatasubramanian Ramachandran Iyer-Natarajan'
            : 'Priya Raman',
        'username': 'priya.raman',
      },
      if (hasOrganisation)
        'enterprise': {
          'code': _orgCode,
          'display': '7454-YKKJ',
          'payload': orgLink,
          'url': hasUrl ? orgLink : null,
          'name': org,
          'location': isLong ? null : {'city': 'Chennai', 'country': 'India'},
          'categories': <String>[],
          'setupDone': true,
        },
      if (hasOrganisation && hasBranches)
        'branches': [
          for (final b in branches)
            {
              'name': b[0],
              'city': b[1],
              'payload': _link(
                '$_orgCode?branch=${Uri.encodeComponent(b[0]!)}',
              ),
              'url': hasUrl
                  ? _link('$_orgCode?branch=${Uri.encodeComponent(b[0]!)}')
                  : null,
            },
        ],
    };
  }
}
