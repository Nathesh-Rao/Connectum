import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:connectum/core/widgets/widgets.dart';

/// Release builds show [AppFriendlyError] instead of Flutter's error box;
/// debug keeps the default red box.
void installErrorWidget({bool isRelease = kReleaseMode}) {
  if (!isRelease) return;
  ErrorWidget.builder = (_) => const AppFriendlyError();
}
