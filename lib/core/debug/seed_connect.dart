import '../../data/api/api_client.dart';
import '../../data/models/connect_card.dart';
import '../../data/repositories/auth_repository.dart';
import '../utils/connect_code.dart';

/// Debug-only fixtures for the QR join flow (SEED_UI=1): fake scan results for
/// every state, no server. Remove before release (see CLAUDE.md).
class SeedConnect {
  SeedConnect._();

  /// Raw strings the "Simulate scan" chips feed into the parser.
  static const presets = [
    (
      'Needs approval',
      'https://connectum.app/connect/7K2M9QWX?branch=Main%20Clinic',
    ),
    ('Joins at once', 'connectum://connect/4DF8TRN3'),
    ('Person QR', 'https://connectum.app/connect/KVZDHDQD?org=7K2M9QWX'),
    ('Already a member', 'connectum:CMYDZ063'),
    ('Waiting already', 'NW7D-3QPX'),
    ('Rejected before', '8RCH4RD1'),
    ('Not found', 'ZZZZZZZZ'),
    ('Rate limited', 'RATE0001'),
    ('Offline', '0FF11NE1'),
    ('Not Connectum', 'https://example.com/connect/7K2M9QWX'),
  ];

  static const _clinic = ConnectCard(
    code: '7K2M9QWX',
    display: '7K2M-9QWX',
    name: 'Harbor Clinic',
    location: 'Chennai, India',
    categories: ['Patient', 'Visitor', 'Vendor'],
  );

  static const _cards = {
    '7K2M9QWX': _clinic,
    '4DF8TRN3': ConnectCard(
      code: '4DF8TRN3',
      display: '4DF8-TRN3',
      name: 'Lakeside School',
      location: 'Bengaluru, India',
      categories: ['Student', 'Parent'],
    ),
    'CMYDZ063': ConnectCard(
      code: 'CMYDZ063',
      display: 'CMYD-Z063',
      name: 'Agile Labs',
      location: 'Bengaluru, India',
      categories: ['Employee', 'Customer'],
    ),
    'NW7D3QPX': ConnectCard(
      code: 'NW7D3QPX',
      display: 'NW7D-3QPX',
      name: 'Northwind Traders',
      location: 'Pune, India',
      categories: ['Vendor'],
    ),
    '8RCH4RD1': ConnectCard(
      code: '8RCH4RD1',
      display: '8RCH-4RD1',
      name: 'Orchard Co-op',
      location: '',
      categories: ['Vendor', 'Customer'],
    ),
  };

  static List<EnterpriseHit> search(String query) {
    final q = query.toLowerCase();
    return [
      for (final c in _cards.values)
        if (c.name.toLowerCase().contains(q))
          EnterpriseHit(c.display, c.name, c.location),
    ];
  }

  static Future<ConnectCard> resolve(ConnectCode link) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final key = link.isPersonLink ? link.org! : link.code;
    switch (key) {
      case 'RATE0001':
        throw const ApiException(
          'rate_limited',
          '',
          status: 429,
          details: {'retryAfter': 42},
        );
      case '0FF11NE1':
        throw const ApiException('network', '');
    }
    final card = _cards[key];
    if (card == null) throw const ApiException('not_found', '', status: 404);
    return ConnectCard(
      code: card.code,
      display: card.display,
      name: card.name,
      location: card.location,
      categories: card.categories,
      branch: link.branch != null && card.code == '7K2M9QWX'
          ? link.branch
          : null,
      isFromPersonLink: link.isPersonLink,
    );
  }

  /// What `POST /join` answers: the Harbor Clinic needs approval.
  static Future<Map<String, dynamic>> join(ConnectCard card) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final isApproval = card.code == _clinic.code;
    return {
      'joined': true,
      'status': isApproval ? 'pending' : 'active',
      'nextStep': isApproval ? 'approval' : 'enter',
      'welcome': isApproval ? '' : 'Welcome to ${card.name}.',
    };
  }
}
