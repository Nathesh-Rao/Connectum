import 'package:flutter/foundation.dart';

import '../../demo/demo_mode.dart';

/// Owner decision: the person's email and the organisation name are sent as
/// Crashlytics keys. Switch either off here (one line each).
const kCrashIncludeEmail = true;
const kCrashIncludeOrgName = true;

class CrashConfig {
  const CrashConfig({
    this.includeEmail = kCrashIncludeEmail,
    this.includeOrgName = kCrashIncludeOrgName,
  });

  final bool includeEmail;
  final bool includeOrgName;
}

const _isFlagged = bool.fromEnvironment('CRASH_REPORTING');

/// Release builds report; debug and profile builds only with
/// `--dart-define=CRASH_REPORTING=true`; the demo never reports.
bool crashCollectionEnabled({
  required bool isDemo,
  required bool isRelease,
  required bool isFlagged,
}) => !isDemo && (isRelease || isFlagged);

bool get isCrashCollectionOn => crashCollectionEnabled(
  isDemo: DemoMode.isActive,
  isRelease: kReleaseMode,
  isFlagged: _isFlagged,
);
