import 'package:flutter/foundation.dart';

import '../data/models/identity_info.dart';

/// Offline demo (`--dart-define=DEMO_MODE=true`, never in release). Everything
/// in `lib/demo/` is removed before release (see CLAUDE.md). It builds on the
/// `SEED_UI` fixtures, which it switches on.
class DemoMode {
  DemoMode._();

  static const _requested = bool.fromEnvironment('DEMO_MODE');

  static bool get isActive => !kReleaseMode && _requested;

  static const otpHint = '123456';
  static const username = 'alex';
  static const personName = 'Alex Morgan';
  static const connectumId = 'MN68-2CQ9';
  static const orgs = [
    ('Agile Labs', 'CMYD-Z063'),
    ('Agile Space', 'WR4Q-BHSK'),
  ];

  static IdentityInfo identity(String email) => IdentityInfo(
    token: 'demo',
    email: email.trim().isEmpty ? 'alex@example.com' : email.trim(),
    connectumId: connectumId,
    name: personName,
    username: username,
    enterprises: [
      for (final (name, id) in orgs)
        EnterpriseMembership(
          enterprise: id,
          name: name,
          city: 'Chennai',
          category: '',
          username: username,
          status: 'active',
        ),
    ],
  );
}
