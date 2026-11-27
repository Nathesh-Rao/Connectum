import 'package:flutter/painting.dart';

import '../../data/profile/presence.dart';
import 'app_colors.dart';
import 'app_tones.dart';

/// The colour of each presence: available green, busy and do not disturb red,
/// in a meeting the primary, away violet.
class AppPresenceTones {
  AppPresenceTones._();

  static AppTone of(Presence p) => switch (p) {
    Presence.available => AppTones.green,
    Presence.busy || Presence.dnd => AppTones.red,
    Presence.meeting => AppTones.primary,
    Presence.away => AppTones.violet,
  };

  /// The dot and the ring.
  static Color dot(Presence p) =>
      p == Presence.available ? AppColors.yesDot : of(p).solid;
}
