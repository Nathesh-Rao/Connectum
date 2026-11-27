import 'package:flutter/foundation.dart';

import 'package:connectum/data/models/models.dart';

/// Offline demo (`--dart-define=DEMO_MODE=true`, never in release). Everything
/// in `lib/demo/` is removed before release (see CLAUDE.md). It builds on the
/// `SEED_UI` fixtures, which it switches on.
class DemoMode {
  DemoMode._();

  static const _requested = bool.fromEnvironment('DEMO_MODE');

  /// The single place `DEMO_MODE` is read: a release build ignores it.
  static bool resolve({required bool isRelease, required bool requested}) =>
      !isRelease && requested;

  static bool get isActive =>
      resolve(isRelease: kReleaseMode, requested: _requested);

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
