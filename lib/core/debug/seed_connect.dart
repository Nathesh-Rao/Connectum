import '../../data/api/api_client.dart';
import '../../data/models/connect_card.dart';
import '../../data/models/connect_lookup.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/socket/socket_service.dart';
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
    'WR4QBHSK': ConnectCard(
      code: 'WR4QBHSK',
      display: 'WR4Q-BHSK',
      name: 'Agile Space',
      location: 'Bengaluru, India',
      categories: ['Employee'],
    ),
    '8RCH4RD1': ConnectCard(
      code: '8RCH4RD1',
      display: '8RCH-4RD1',
      name: 'Orchard Co-op',
      location: '',
      categories: ['Vendor', 'Customer'],
    ),
  };

  /// Links for the confirm sheet (`/debug/connect`, with SEED_UI=1). The
  /// current sample organisation is Agile Labs (CMYDZ063).
  static const targetPresets = [
    (
      'Person: confirm, then connect',
      'https://connectum.app/connect/KVZDHDQD?org=CMYDZ063',
    ),
    (
      'Person: name only',
      'https://connectum.app/connect/MN3P7QZ2?org=CMYDZ063',
    ),
    (
      'Person: already associates',
      'https://connectum.app/connect/A55C1A7E?org=CMYDZ063',
    ),
    (
      'Organisation card (already in)',
      'https://connectum.app/connect/CMYDZ063',
    ),
    (
      'Other organisation: switch (member)',
      'https://connectum.app/connect/WR4QBHSK',
    ),
    (
      'Other organisation: join (not a member)',
      'https://connectum.app/connect/7K2M9QWX?branch=Main%20Clinic',
    ),
    (
      'Person of another organisation: join',
      'https://connectum.app/connect/KVZDHDQD?org=7K2M9QWX',
    ),
    (
      'Other organisation: pending approval',
      'https://connectum.app/connect/NW7D3QPX',
    ),
    ('Other organisation: rejected', 'https://connectum.app/connect/8RCH4RD1'),
    ('Not found', 'https://connectum.app/connect/ZZZZZZZZ'),
    ('Rate limited', 'https://connectum.app/connect/RATE0001?org=CMYDZ063'),
    ('Offline (target kept)', 'https://connectum.app/connect/0FF11NE1'),
  ];

  /// Invites for the welcome and sign-in screens: (label, link). They
  /// need SEED_UI=1; the card then reads the sample organisations above.
  static const invitePresets = [
    (
      'Welcome card: Join Test organisation',
      'https://connectum.app/connect/7K2M9QWX?branch=Main%20Clinic',
    ),
    (
      'Welcome card: person link (organisation only)',
      'https://connectum.app/connect/KVZDHDQD?org=4DF8TRN3',
    ),
    ('Invalid invite', 'https://connectum.app/connect/ZZZZZZZZ'),
    ('Rate-limited card', 'https://connectum.app/connect/RATE0001'),
    ('Card cannot load (offline)', 'https://connectum.app/connect/0FF11NE1'),
  ];

  /// After sign-in (the enterprises screen): waiting for approval, a refusal,
  /// and an organisation the person is not in (opens the join sheet).
  static const chainPresets = [
    (
      'Waiting for approval',
      'https://connectum.app/connect/KVZDHDQD?org=NW7D3QPX',
    ),
    ('Rejected', 'https://connectum.app/connect/8RCH4RD1'),
    ('Not a member: join sheet', 'https://connectum.app/connect/4DF8TRN3'),
  ];

  static const _people = {
    'KVZDHDQD': ConnectPerson(
      name: 'Priya Raman',
      username: 'priya.raman',
      designation: 'Head of Operations',
      department: 'Operations',
    ),
    'MN3P7QZ2': ConnectPerson(name: 'Sam Carter', username: 'sam.carter'),
    'A55C1A7E': ConnectPerson(
      name: 'Dev Patel',
      username: 'dev.patel',
      designation: 'Engineer',
      department: 'Platform',
    ),
  };

  /// What `connect.lookup` / `connect.scan` answer inside Agile Labs.
  static Future<ConnectLookup> target(
    ConnectCode link, {
    required bool isScan,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    switch (link.code) {
      case 'RATE0001':
        throw const SocketCallError('rate_limited', '', {'retryAfter': 420});
      case '0FF11NE1':
        throw const SocketCallError('not_connected');
    }
    final isHere = (link.org ?? link.code) == 'CMYDZ063';
    if (!isHere) {
      throw SocketCallError(link.isPersonLink ? 'wrong_org' : 'not_found');
    }
    if (link.code == 'CMYDZ063') {
      return ConnectLookup.organisation((await resolve(link)));
    }
    final person = _people[link.code];
    if (person == null) throw const SocketCallError('not_found');
    return ConnectLookup.person(person, isConnected: link.code == 'A55C1A7E');
  }

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
