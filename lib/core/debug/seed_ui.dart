import 'package:flutter/foundation.dart';

import '../../data/models/identity_info.dart';

/// Debug-only fixture for UI checks: run with --dart-define=SEED_UI=1 and the
/// enterprises screen shows five sample enterprises. Ignored in release. The
/// data lives in memory only: nothing goes to SQLite, SessionStore or secure
/// storage. Remove before release (see CLAUDE.md).
class SeedUi {
  SeedUi._();

  static const _requested = String.fromEnvironment('SEED_UI') == '1';

  static bool get isActive => kDebugMode && _requested;

  static const currentOrgId = 'CMYD-Z063';
  static const sampleEnterpriseName = 'Agile Labs';

  static IdentityInfo? identity() {
    if (!isActive) return null;
    const names = [
      ('Agile Labs', 'CMYD-Z063'),
      ('Agile Space', 'WR4Q-BHSK'),
      ('Demo HR', 'QC2V-N0ET'),
      ('Demo University', 'EHYS-EAYP'),
      ('Kauvery hospital', '2Z73-TQ5C'),
    ];
    return IdentityInfo(
      token: 'seed',
      email: 'alex@example.com',
      connectumId: 'MN68-2CQ9',
      enterprises: [
        for (final (name, id) in names)
          EnterpriseMembership(
            enterprise: id,
            name: name,
            city: '',
            category: '',
            username: 'alex',
            status: 'active',
          ),
      ],
    );
  }
}
