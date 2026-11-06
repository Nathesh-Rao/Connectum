import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_spacing.dart';

/// Whether the new chat button shows. One flag, written only when it changes:
/// scrolling down by [AppSpacing.fabScrollThreshold] hides it, scrolling up by
/// as much shows it. At the top, on a list too short to scroll and during
/// overscroll it shows or stays as it is.
class NewChatButtonState {
  final isShown = true.obs;

  double _run = 0;

  void show() {
    _run = 0;
    if (!isShown.value) isShown.value = true;
  }

  bool onScroll(ScrollNotification n) {
    if (n.depth != 0 || n is! ScrollUpdateNotification) return false;
    final m = n.metrics;
    if (m.maxScrollExtent <= 0 || m.pixels <= 0) {
      show();
      return false;
    }
    if (m.outOfRange) return false;
    final delta = n.scrollDelta ?? 0;
    if (delta == 0) return false;
    if (_run != 0 && (_run > 0) != (delta > 0)) _run = 0;
    _run += delta;
    if (_run.abs() < AppSpacing.fabScrollThreshold) return false;
    final shouldShow = _run < 0;
    if (isShown.value != shouldShow) isShown.value = shouldShow;
    return false;
  }
}
