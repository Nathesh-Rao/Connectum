import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:connectum/core/theme/theme.dart';
import 'callout_geometry.dart';

/// What the callout looks like at one moment: where each card is (box
/// coordinates), how opaque, how far the cards have joined into one panel and
/// how far the tail has grown.
class CalloutFrame {
  const CalloutFrame({
    required this.cards,
    required this.cardOpacity,
    required this.contentOpacity,
    required this.join,
    required this.tailGrow,
  });

  final List<Rect> cards;
  final List<double> cardOpacity;
  final List<double> contentOpacity;

  /// 0 separate cards, 1 one panel.
  final double join;
  final double tailGrow;
}

/// A panel and its tail as ONE outline: a rounded rectangle with a triangle
/// whose tip is rounded. [rect], [tipX] and [apexY] are in a box of
/// [boxHeight]; when [isUp] the tail is on the bottom edge.
Path calloutPath({
  required Rect rect,
  required double radius,
  required double tipX,
  required double apexY,
  required double grow,
  required bool isUp,
  required double boxHeight,
}) {
  final r = isUp
      ? Rect.fromLTRB(
          rect.left,
          boxHeight - rect.bottom,
          rect.right,
          boxHeight - rect.top,
        )
      : rect;
  final target = isUp ? boxHeight - apexY : apexY;
  final rad = math.min(radius, math.min(r.width, r.height) / 2);
  final half = AppSpacing.calloutTailBaseHalf * grow;
  final lo = r.left + rad + half;
  final hi = r.right - rad - half;
  final cx = lo > hi ? r.center.dx : tipX.clamp(lo, hi).toDouble();
  final apex = Offset(
    cx,
    ui.lerpDouble(r.top, math.min(target, r.top), grow.clamp(0.0, 1.5))!,
  );
  final path = Path()..moveTo(r.left + rad, r.top);
  final left = Offset(cx - half, r.top);
  final right = Offset(cx + half, r.top);
  final slope = (apex - left).distance;
  if (grow > 0.02 && slope > 1) {
    final k = math.min(AppSpacing.calloutTailTipRadius, slope / 2) / slope;
    final p1 = apex + (left - apex) * k;
    final p2 = apex + (right - apex) * k;
    path
      ..lineTo(left.dx, left.dy)
      ..lineTo(p1.dx, p1.dy)
      ..quadraticBezierTo(apex.dx, apex.dy, p2.dx, p2.dy)
      ..lineTo(right.dx, right.dy);
  }
  final corner = Radius.circular(rad);
  path
    ..lineTo(r.right - rad, r.top)
    ..arcToPoint(Offset(r.right, r.top + rad), radius: corner)
    ..lineTo(r.right, r.bottom - rad)
    ..arcToPoint(Offset(r.right - rad, r.bottom), radius: corner)
    ..lineTo(r.left + rad, r.bottom)
    ..arcToPoint(Offset(r.left, r.bottom - rad), radius: corner)
    ..lineTo(r.left, r.top + rad)
    ..arcToPoint(Offset(r.left + rad, r.top), radius: corner)
    ..close();
  if (!isUp) return path;
  return path.transform(
    Matrix4(1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, boxHeight, 0, 1).storage,
  );
}

void _paintShape(
  Canvas canvas,
  Path path, {
  required double shadow,
  required double border,
  required double fill,
}) {
  if (shadow > 0) {
    for (final s in AppShadows.soft) {
      canvas.drawPath(
        path.shift(s.offset),
        BoxShadow(
          color: s.color.withValues(alpha: s.color.a * shadow.clamp(0.0, 1.0)),
          blurRadius: s.blurRadius,
          spreadRadius: s.spreadRadius,
        ).toPaint(),
      );
    }
  }
  canvas.drawPath(
    path,
    Paint()..color = AppColors.white.withValues(alpha: fill.clamp(0.0, 1.0)),
  );
  if (border > 0) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.cardLine.withValues(alpha: border.clamp(0.0, 1.0)),
    );
  }
}

class CalloutPainter extends CustomPainter {
  const CalloutPainter({required this.geometry, required this.frame});

  final CalloutGeometry geometry;
  final CalloutFrame frame;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final f = frame;
    final near = g.nearIndex;
    final radius = AppRadius.card;
    final others = [
      for (var i = 0; i < g.count; i++)
        if (i != near) i,
    ]..sort((a, b) => (b - near).abs().compareTo((a - near).abs()));
    for (final i in others) {
      final o = f.cardOpacity[i];
      if (o <= 0.01 || f.cards[i].isEmpty) continue;
      final path = Path()
        ..addRRect(
          RRect.fromRectAndRadius(f.cards[i], Radius.circular(radius)),
        );
      _paintShape(
        canvas,
        path,
        shadow: (1 - f.join) * o,
        border: (1 - f.join) * o,
        fill: o,
      );
    }
    final o = f.cardOpacity[near];
    if (o <= 0.01) return;
    final body = Rect.lerp(f.cards[near], g.fullBody, f.join)!;
    final path = calloutPath(
      rect: body,
      radius: radius,
      tipX: g.tipX,
      apexY: g.apexY,
      grow: f.tailGrow,
      isUp: g.isUp,
      boxHeight: g.box.height,
    );
    _paintShape(canvas, path, shadow: o, border: o, fill: o);
  }

  @override
  bool shouldRepaint(CalloutPainter old) => true;
}
