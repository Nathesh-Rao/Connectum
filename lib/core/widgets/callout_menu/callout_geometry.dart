import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:connectum/core/theme/theme.dart';
import '../animated_callout_menu.dart';

/// Where a menu goes for an anchor: right-aligned under it when it fits, above
/// it when that has more room, never off screen. Row heights are measured once
/// here, so the size is exact and nothing is measured during the animation.
class CalloutGeometry {
  CalloutGeometry({
    required this.anchor,
    required this.media,
    required List<MenuItem<Object?>> items,
    required this.isRtl,
  }) : count = items.length {
    final screen = media.size;
    final safe = media.padding + media.viewInsets;
    final margin = AppSpacing.popupMenuMargin;
    final scale = math.max(1.0, media.textScaler.scale(1));
    width = math.min(
      screen.width - 2 * margin,
      math.max(AppSpacing.compactMenuMinWidth, AppSpacing.calloutWidth * scale),
    );
    heights = [for (final item in items) _rowHeight(item)];
    bodyHeight = heights.fold(0.0, (a, b) => a + b) + 2 * AppSpacing.xxs;
    final boxHeight = bodyHeight + AppSpacing.calloutTailHeight;
    final below =
        screen.height -
        safe.bottom -
        anchor.bottom -
        AppSpacing.xxs -
        AppSpacing.xs;
    final above = anchor.top - safe.top - AppSpacing.xxs - AppSpacing.xs;
    isUp = boxHeight > below && above > below;
    final edge = isRtl ? anchor.left : anchor.right - width;
    final left = edge
        .clamp(margin, math.max(margin, screen.width - margin - width))
        .toDouble();
    final wantedTop = isUp
        ? anchor.top - AppSpacing.xxs - boxHeight
        : anchor.bottom + AppSpacing.xxs;
    final minTop = safe.top;
    final maxTop = math.max(minTop, screen.height - safe.bottom - boxHeight);
    box = Rect.fromLTWH(
      left,
      wantedTop.clamp(minTop, maxTop).toDouble(),
      width,
      boxHeight,
    );
  }

  final Rect anchor;
  final MediaQueryData media;
  final int count;
  final bool isRtl;

  late final double width;
  late final double bodyHeight;
  late final bool isUp;
  late final List<double> heights;

  /// The menu with its tail room, in screen coordinates.
  late final Rect box;

  double _rowHeight(MenuItem<Object?> item) {
    final textWidth =
        width -
        2 * AppSpacing.compactMenuPadding -
        (item.icon == null
            ? 0
            : AppSpacing.compactMenuIconSlot + AppSpacing.sm);
    double measure(String text, TextStyle style) {
      if (text.isEmpty) return 0;
      final p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        textScaler: media.textScaler,
      )..layout(maxWidth: math.max(0, textWidth));
      final h = p.height;
      p.dispose();
      return h;
    }

    final label = measure(item.label, AppText.menuItem);
    final why = measure(item.why, AppText.caption);
    final pad = (item.icon == null ? AppSpacing.sm : AppSpacing.xxs) * 2;
    return math.max(AppSpacing.compactMenuRow, pad + label + why);
  }

  /// The row nearest the anchor: the one that comes out first.
  int get nearIndex => isUp ? count - 1 : 0;

  double get bodyTop => isUp ? 0 : AppSpacing.calloutTailHeight;

  /// The whole panel in the box's own coordinates.
  Rect get fullBody => Rect.fromLTWH(0, bodyTop, width, bodyHeight);

  /// Row [i] in its place, in the box's own coordinates.
  Rect cardRect(int i) {
    var top = bodyTop + AppSpacing.xxs;
    for (var k = 0; k < i; k++) {
      top += heights[k];
    }
    return Rect.fromLTWH(0, top, width, heights[i]);
  }

  Offset get anchorLocal => anchor.center - box.topLeft;

  /// Where the tail's tip touches the anchor side, across the box.
  double get tipX => anchorLocal.dx;

  /// The tip's height in the box: its top edge, or its bottom edge when flipped.
  double get apexY => isUp ? box.height : 0;
}
