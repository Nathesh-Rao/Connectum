import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:connectum/core/theme/theme.dart';
import 'callout_menu/callout_geometry.dart';
import 'callout_menu/callout_painter.dart';
import 'callout_menu/callout_row.dart';

/// One row of an [AnimatedCalloutMenu]. [value] is what the menu returns when
/// the row is tapped. A row that is off ([isEnabled] false) shows [why] under
/// the label and does nothing.
class MenuItem<T> {
  const MenuItem({
    required this.label,
    required IconData this.icon,
    required T this.value,
    this.why = '',
    this.isEnabled = true,
    this.isDanger = false,
    this.hasDividerAbove = false,
  });

  /// A line of text without an icon and without a tap ("Loading…").
  const MenuItem.note(this.label)
    : icon = null,
      value = null,
      why = '',
      isEnabled = false,
      isDanger = false,
      hasDividerAbove = false;

  final String label;
  final IconData? icon;
  final T? value;
  final String why;
  final bool isEnabled;
  final bool isDanger;

  /// An inset hairline above the row once the cards are one panel.
  final bool hasDividerAbove;
}

/// The three-dot menu of a card. The row nearest the anchor pops out of it
/// with a tail that grows with it; the other rows slide out from under it one
/// after another as a stack, then the gaps close and everything is one panel
/// with the tail in the same outline. Closing is the same timeline backwards.
///
/// It opens right-aligned under the anchor, or above it when that has more
/// room, and never off screen. A tap outside, back or Escape closes it. Text
/// is scaled up to 1.5x. With reduced motion the menu only fades.
class AnimatedCalloutMenu {
  AnimatedCalloutMenu._();

  /// The anchor of the widget of [context] in screen coordinates, or null
  /// when it is not laid out.
  static Rect? anchorOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Opens the menu and returns the [MenuItem.value] of the tapped row (null
  /// when it is closed without a pick). [live], when given, replaces [items]
  /// while the menu is open (rows that change after it opened).
  static Future<T?> show<T>(
    BuildContext context,
    Rect anchor,
    List<MenuItem<T>> items, {
    String label = 'Menu',
    ValueListenable<List<MenuItem<T>>>? live,
  }) {
    final source = live ?? ValueNotifier<List<MenuItem<T>>>(items);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final isStill = MediaQuery.disableAnimationsOf(context);
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: isStill
          ? AppDurations.reduced
          : AppDurations.calloutMenu,
      pageBuilder: (ctx, animation, _) {
        final raw = MediaQuery.of(ctx);
        final media = raw.copyWith(
          textScaler: raw.textScaler.clamp(
            minScaleFactor: 1,
            maxScaleFactor: 1.5,
          ),
        );
        return MediaQuery(
          data: media,
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            label: label,
            explicitChildNodes: true,
            onDismiss: () => Navigator.of(ctx).maybePop(),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    Navigator.of(ctx).maybePop(),
              },
              child: FocusScope(
                autofocus: true,
                child: Material(
                  type: MaterialType.transparency,
                  child: ValueListenableBuilder<List<MenuItem<T>>>(
                    valueListenable: source,
                    builder: (_, rows, _) => rows.isEmpty
                        ? const SizedBox.shrink()
                        : _CalloutBody<T>(
                            geometry: CalloutGeometry(
                              anchor: anchor,
                              media: media,
                              items: rows,
                              isRtl: isRtl,
                            ),
                            t: isStill
                                ? const AlwaysStoppedAnimation<double>(1)
                                : animation,
                            items: rows,
                            onPick: (item) => Navigator.of(ctx).pop(item.value),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) =>
          isStill ? FadeTransition(opacity: animation, child: child) : child,
    );
  }
}

/// The cards and the tail, all drawn in one painter and moved by transforms,
/// so nothing is laid out while it plays.
class _CalloutBody<T> extends StatelessWidget {
  const _CalloutBody({
    required this.geometry,
    required this.t,
    required this.items,
    required this.onPick,
  });

  final CalloutGeometry geometry;
  final Animation<double> t;
  final List<MenuItem<T>> items;
  final ValueChanged<MenuItem<T>> onPick;

  @override
  Widget build(BuildContext context) {
    final g = geometry;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: g.box,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {},
            child: AnimatedBuilder(
              animation: t,
              builder: (context, _) {
                final f = _frame(t.value, g);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: CalloutPainter(geometry: g, frame: f),
                      ),
                    ),
                    for (var i = 0; i < items.length; i++)
                      Positioned.fromRect(
                        rect: g.cardRect(i),
                        child: _Moved(
                          from: g.cardRect(i),
                          to: f.cards[i],
                          opacity: f.contentOpacity[i],
                          child: CalloutRow(
                            item: items[i],
                            height: g.heights[i],
                            dividerAlpha: f.join,
                            onTap: () => onPick(items[i]),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  static CalloutFrame _frame(double t, CalloutGeometry g) {
    final near = g.nearIndex;
    final join = AppCurves.inOut.transform(
      const Interval(0.74, 1).transform(t),
    );
    final pop = AppCurves.softOvershoot.transform(
      const Interval(0, 0.28).transform(t),
    );
    final gap = AppSpacing.xs * (1 - join);
    final nearFinal = g.cardRect(near);
    final cards = <Rect>[];
    final cardOpacity = <double>[];
    final contentOpacity = <double>[];
    for (var i = 0; i < g.count; i++) {
      final fin = g.cardRect(i);
      final ord = (i - near).abs();
      if (ord == 0) {
        final scale = 0.25 + 0.75 * pop;
        cards.add(
          Rect.fromCenter(
            center: Offset.lerp(g.anchorLocal, fin.center, pop)!,
            width: fin.width * scale,
            height: fin.height * scale,
          ),
        );
        cardOpacity.add(const Interval(0, 0.12).transform(t));
        contentOpacity.add(const Interval(0.14, 0.3).transform(t));
        continue;
      }
      final start = 0.26 + (ord - 1) * 0.16;
      final e = AppCurves.out.transform(
        Interval(start, start + 0.3).transform(t),
      );
      final top =
          nearFinal.top + (fin.top + (i - near) * gap - nearFinal.top) * e;
      cards.add(Rect.fromLTWH(fin.left, top, fin.width, fin.height));
      cardOpacity.add(e > 0 ? 1 : 0);
      contentOpacity.add(const Interval(0.45, 1).transform(e));
    }
    return CalloutFrame(
      cards: cards,
      cardOpacity: cardOpacity,
      contentOpacity: contentOpacity,
      join: join,
      tailGrow: AppCurves.out.transform(const Interval(0.1, 0.42).transform(t)),
    );
  }
}

/// Paints [child] moved and scaled from its place [from] to the card [to].
class _Moved extends StatelessWidget {
  const _Moved({
    required this.from,
    required this.to,
    required this.opacity,
    required this.child,
  });

  final Rect from;
  final Rect to;
  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = from.width == 0 ? 1.0 : to.width / from.width;
    final move = to.center - from.center;
    final o = opacity.clamp(0.0, 1.0);
    return IgnorePointer(
      ignoring: o < 0.6,
      child: Opacity(
        opacity: o,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(move.dx, move.dy, 0, 1)
            ..scaleByDouble(scale, scale, 1, 1),
          child: child,
        ),
      ),
    );
  }
}
