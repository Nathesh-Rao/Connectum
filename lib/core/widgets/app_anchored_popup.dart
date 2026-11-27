import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';

/// A floating menu anchored to the widget of a context: below it when it
/// fits, above it when that has more room, never off screen. Tapping outside
/// or back closes it. It scrolls when it is taller than the room and wraps its
/// content between the compact menu's min and max width.
///
/// Opening: each [AppPopupItem] of the content comes out of the anchor as its
/// own rounded card, one after another ([AppDurations.popupStagger] apart, with
/// a soft overshoot); then the gaps close and the cards become one menu surface
/// with the shadow. Closing is the same sequence backwards. With reduced
/// motion the menu only fades.
class AppAnchoredPopup {
  AppAnchoredPopup._();

  static Future<void> show(
    BuildContext anchor, {
    required String label,
    required WidgetBuilder builder,
  }) {
    final box = anchor.findRenderObject();
    if (box is! RenderBox || !box.attached) return Future.value();
    final target = box.localToGlobal(Offset.zero) & box.size;
    final isStill = MediaQuery.disableAnimationsOf(anchor);
    return showGeneralDialog<void>(
      context: anchor,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: isStill
          ? AppDurations.reduced
          : AppDurations.popupMenu,
      pageBuilder: (context, animation, _) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 1,
              maxScaleFactor: 1.5,
            ),
          ),
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            label: label,
            explicitChildNodes: true,
            onDismiss: () => Navigator.of(context).maybePop(),
            child: FocusTraversalGroup(
              child: AppPopupStage(
                animation: animation,
                anchor: target.center,
                isStill: isStill,
                child: CustomSingleChildLayout(
                  delegate: _PopupLayout(
                    target: target,
                    isRtl: Directionality.of(context) == TextDirection.rtl,
                    padding: media.padding + media.viewInsets,
                  ),
                  child: _Surface(child: Builder(builder: builder)),
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

/// The timeline of the menu's opening on the route's 0..1 animation, shared
/// by the items and the surface. Closing plays the same values backwards.
class AppPopupTiming {
  AppPopupTiming._();

  static final double _total = AppDurations.popupMenu.inMilliseconds.toDouble();

  /// Items after the third arrive with it.
  static const _lastStaggered = 2;

  /// How far item [index] has come out of the anchor at timeline [t]
  /// (0 inside the anchor, 1 in place; it passes 1 a little).
  static double enter(int index, double t) {
    final start =
        math.min(index, _lastStaggered) *
        AppDurations.popupStagger.inMilliseconds;
    final raw = Interval(
      start / _total,
      (start + AppDurations.popupItem.inMilliseconds) / _total,
    ).transform(t);
    return AppCurves.softOvershoot.transform(raw);
  }

  /// How far the gaps have closed and the cards have become one surface
  /// (0 separate cards, 1 one menu); only after the items are out.
  static double merge(double t) => Interval(
    1 - AppDurations.popupMerge.inMilliseconds / _total,
    1,
    curve: AppCurves.inOut,
  ).transform(t);
}

/// Gives the [AppPopupItem]s under it the opening's animation and the
/// anchor's centre.
class AppPopupStage extends InheritedWidget {
  const AppPopupStage({
    super.key,
    required this.animation,
    required this.anchor,
    required this.isStill,
    required super.child,
  });

  final Animation<double> animation;

  /// The anchor's centre in screen coordinates.
  final Offset anchor;
  final bool isStill;

  static AppPopupStage? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppPopupStage>();

  @override
  bool updateShouldNotify(AppPopupStage old) =>
      old.animation != animation ||
      old.anchor != anchor ||
      old.isStill != isStill;
}

/// One row of the menu as its own card. Under an [AppAnchoredPopup] it flies
/// out of the anchor in its turn and merges into the menu; anywhere else it is
/// just [child]. [index] and [count] place it in the list, and
/// [hasDividerAbove] draws the inset hairline once the cards are one menu.
class AppPopupItem extends StatelessWidget {
  const AppPopupItem({
    super.key,
    required this.index,
    required this.count,
    required this.child,
    this.hasDividerAbove = false,
  });

  final int index;
  final int count;
  final Widget child;
  final bool hasDividerAbove;

  @override
  Widget build(BuildContext context) {
    final stage = AppPopupStage.maybeOf(context);
    if (stage == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [if (hasDividerAbove) _divider(1), child],
      );
    }
    return AnimatedBuilder(
      animation: stage.animation,
      builder: (context, _) {
        final t = stage.animation.value;
        final enter = stage.isStill ? 1.0 : AppPopupTiming.enter(index, t);
        final merge = stage.isStill ? 1.0 : AppPopupTiming.merge(t);
        final isFirst = index == 0;
        final isLast = index == count - 1;
        final radius = AppRadius.card;
        final borderRadius = BorderRadius.vertical(
          top: Radius.circular(isFirst ? radius : radius * (1 - merge)),
          bottom: Radius.circular(isLast ? radius : radius * (1 - merge)),
        );
        final gap = isLast ? 0.0 : AppSpacing.xs * (1 - merge);
        final card = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: _fade(AppShadows.soft, 1 - merge),
          ),
          child: Material(
            color: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius,
              side: BorderSide(
                color: AppColors.cardLine.withValues(alpha: 1 - merge),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: EdgeInsets.only(
                top: isFirst ? AppSpacing.xxs : 0,
                bottom: isLast ? AppSpacing.xxs : 0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [if (hasDividerAbove) _divider(merge), child],
              ),
            ),
          ),
        );
        return Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: stage.isStill
              ? card
              : IgnorePointer(
                  ignoring: enter < 0.05,
                  child: Opacity(
                    opacity: (enter * 2).clamp(0.0, 1.0),
                    child: _Fly(
                      anchor: stage.anchor,
                      progress: enter,
                      child: card,
                    ),
                  ),
                ),
        );
      },
    );
  }

  static Widget _divider(double alpha) => Divider(
    height: 1,
    color: AppColors.cardLine.withValues(alpha: alpha.clamp(0.0, 1.0)),
    indent: AppSpacing.compactMenuPadding,
    endIndent: AppSpacing.compactMenuPadding,
  );

  static List<BoxShadow> _fade(List<BoxShadow> shadows, double by) => [
    for (final s in shadows)
      BoxShadow(
        color: s.color.withValues(alpha: s.color.a * by.clamp(0.0, 1.0)),
        blurRadius: s.blurRadius,
        offset: s.offset,
        spreadRadius: s.spreadRadius,
      ),
  ];
}

/// Paints its child scaled and moved toward [anchor] by `1 - progress`: at 0
/// it sits small on the anchor, at 1 in place. Hit tests follow the paint.
class _Fly extends SingleChildRenderObjectWidget {
  const _Fly({required this.anchor, required this.progress, super.child});

  final Offset anchor;
  final double progress;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFly(anchor: anchor, progress: progress);

  @override
  void updateRenderObject(BuildContext context, _RenderFly renderObject) {
    renderObject
      ..anchor = anchor
      ..progress = progress;
  }
}

class _RenderFly extends RenderProxyBox {
  _RenderFly({required Offset anchor, required double progress})
    : _anchor = anchor,
      _progress = progress;

  static const _minScale = 0.3;

  Offset _anchor;
  set anchor(Offset v) {
    if (v == _anchor) return;
    _anchor = v;
    markNeedsPaint();
  }

  double _progress;
  set progress(double v) {
    if (v == _progress) return;
    _progress = v;
    markNeedsPaint();
  }

  Matrix4? get _matrix {
    if (!hasSize || !attached || _progress == 1) return null;
    final center = size.center(Offset.zero);
    final move = (_anchor - localToGlobal(center)) * (1 - _progress);
    final scale = _minScale + (1 - _minScale) * _progress;
    return Matrix4.identity()
      ..translateByDouble(move.dx + center.dx, move.dy + center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final m = _matrix;
    if (m == null) {
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      m,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final m = _matrix;
    if (m != null) transform.multiply(m);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final m = _matrix;
    if (m == null) return super.hitTestChildren(result, position: position);
    return result.addWithPaintTransform(
      transform: m,
      position: position,
      hitTest: (result, position) =>
          child?.hitTest(result, position: position) ?? false,
    );
  }
}

/// The menu's frame: the shadow and the outline appear as the cards merge. It
/// scrolls when the room is short.
class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final stage = AppPopupStage.maybeOf(context);
    final animation = stage?.animation;
    return AnimatedBuilder(
      animation: animation ?? const AlwaysStoppedAnimation<double>(1),
      builder: (context, _) {
        final t = animation?.value ?? 1;
        final merge = stage == null || stage.isStill
            ? 1.0
            : AppPopupTiming.merge(t);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardAll,
            boxShadow: AppPopupItem._fade(AppShadows.soft, merge),
          ),
          position: DecorationPosition.background,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppRadius.cardAll,
              border: Border.all(
                color: AppColors.cardLine.withValues(alpha: merge),
              ),
            ),
            position: DecorationPosition.foreground,
            child: SingleChildScrollView(
              clipBehavior: t >= 1 ? Clip.hardEdge : Clip.none,
              child: IntrinsicWidth(child: child),
            ),
          ),
        );
      },
    );
  }
}

class _PopupLayout extends SingleChildLayoutDelegate {
  _PopupLayout({
    required this.target,
    required this.isRtl,
    required this.padding,
  });

  final Rect target;
  final bool isRtl;
  final EdgeInsets padding;

  static const _gap = 4.0;

  double _below(Size s) =>
      s.height - padding.bottom - target.bottom - _gap - AppSpacing.xs;

  double _above(Size s) => target.top - padding.top - _gap - AppSpacing.xs;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) {
    final s = c.biggest;
    final screenMax = math.max(0.0, s.width - 2 * AppSpacing.popupMenuMargin);
    final maxWidth = math.min(
      screenMax,
      math.max(
        AppSpacing.compactMenuMinWidth,
        math.min(
          AppSpacing.compactMenuMaxWidth,
          s.width * AppSpacing.compactMenuMaxFraction,
        ),
      ),
    );
    final room = math.max(_below(s), _above(s));
    return BoxConstraints(
      minWidth: math.min(AppSpacing.compactMenuMinWidth, maxWidth),
      maxWidth: maxWidth,
      maxHeight: math.max(0, room),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final margin = AppSpacing.popupMenuMargin;
    final edge = isRtl ? target.left : target.right - child.width;
    final left = edge
        .clamp(margin, math.max(margin, size.width - margin - child.width))
        .toDouble();
    final fitsBelow = child.height <= _below(size);
    final top = fitsBelow || _below(size) >= _above(size)
        ? target.bottom + _gap
        : target.top - _gap - child.height;
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_PopupLayout old) =>
      old.target != target || old.isRtl != isRtl || old.padding != padding;
}
