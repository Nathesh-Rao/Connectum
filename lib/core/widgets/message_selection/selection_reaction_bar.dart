import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../selection/message_selection.dart';
import 'package:connectum/core/theme/theme.dart';

/// The floating pill above (or below) the selected message: the quick emoji,
/// scrolling when they do not fit, and a round "+" that always stays visible.
class SelectionReactionBar extends StatelessWidget {
  const SelectionReactionBar({
    super.key,
    required this.emojis,
    required this.mine,
    required this.onPick,
    required this.onMore,
  });

  static const height = 52.0;
  static const cell = AppSpacing.minTapTarget;

  final List<String> emojis;

  /// The emoji I already used on this message; they are filled.
  final Set<String> mine;
  final void Function(String emoji) onPick;
  final VoidCallback onMore;

  /// The width the pill wants when everything fits.
  static double idealWidth(int count) => (count + 1) * cell + AppSpacing.xs * 2;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.pillAll,
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final e in emojis)
                  _Cell(
                    label: e,
                    isMine: mine.contains(e),
                    onTap: () => onPick(e),
                    child: Text(
                      e,
                      textScaler: scaler,
                      style: const TextStyle(fontSize: 22, height: 1.2),
                    ),
                  ),
              ],
            ),
          ),
          _Cell(
            label: 'More reactions',
            isMine: false,
            isFilled: true,
            onTap: onMore,
            child: const Icon(Icons.add, size: 22, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.isMine,
    required this.onTap,
    required this.child,
    this.isFilled = false,
  });

  final String label;
  final bool isMine;
  final bool isFilled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: isMine,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: SelectionReactionBar.cell,
        height: SelectionReactionBar.cell,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isMine || isFilled ? AppColors.primaryTint : null,
          shape: BoxShape.circle,
        ),
        child: child,
      ),
    ),
  );
}

/// Puts [bar] over the thread next to the selected row: above it, or below it
/// when there is no room above, always inside the safe area. It plays a short
/// scale and fade, hides itself when the thread scrolls and shows again with
/// the next selection change. Place it in a Stack over the message list.
class SelectionBarOverlay extends StatefulWidget {
  const SelectionBarOverlay({
    super.key,
    required this.selection,
    required this.isShown,
    required this.barWidth,
    required this.bar,
    required this.scroll,
  });

  final MessageSelection selection;

  /// True when exactly one message is selected and it takes reactions.
  final bool Function() isShown;
  final double barWidth;
  final Widget Function(double width) bar;
  final ScrollController scroll;

  @override
  State<SelectionBarOverlay> createState() => _SelectionBarOverlayState();
}

class _SelectionBarOverlayState extends State<SelectionBarOverlay> {
  static const _gap = AppSpacing.xs;
  Rect? _anchor;
  String? _measured;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(SelectionBarOverlay old) {
    super.didUpdateWidget(old);
    if (old.scroll != widget.scroll) {
      old.scroll.removeListener(_onScroll);
      widget.scroll.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() => widget.selection.hideBar();

  void _measure(String id) {
    final target = widget.selection.anchorOf(id).currentContext;
    final mine = context;
    if (!mounted || target == null || !target.mounted) return;
    final box = target.findRenderObject();
    final me = mine.findRenderObject();
    if (box is! RenderBox || me is! RenderBox || !box.hasSize) return;
    final topLeft = me.globalToLocal(box.localToGlobal(Offset.zero));
    final rect = topLeft & box.size;
    if (_measured == id && _anchor == rect) return;
    setState(() {
      _measured = id;
      _anchor = rect;
    });
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final id = widget.selection.only;
    final isVisible =
        id != null && !widget.selection.isBarHidden.value && widget.isShown();
    if (!isVisible) {
      _anchor = null;
      _measured = null;
      return const SizedBox.shrink();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure(id));
    final rect = _measured == id ? _anchor : null;
    return LayoutBuilder(
      builder: (context, box) {
        if (rect == null) return const SizedBox.shrink();
        final pad = MediaQuery.paddingOf(context);
        final width = widget.barWidth.clamp(
          0.0,
          box.maxWidth - 2 * AppSpacing.xs - pad.left - pad.right,
        );
        const h = SelectionReactionBar.height;
        final minTop = pad.top + _gap;
        final maxTop = box.maxHeight - pad.bottom - h - _gap;
        var top = rect.top - h - _gap;
        if (top < minTop) top = rect.bottom + _gap;
        top = top.clamp(minTop, maxTop < minTop ? minTop : maxTop);
        final isMine = rect.center.dx > box.maxWidth / 2;
        var left = isMine ? rect.right - width : rect.left;
        left = left.clamp(
          pad.left + AppSpacing.xs,
          box.maxWidth - pad.right - AppSpacing.xs - width,
        );
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(id),
                tween: Tween(begin: 0.6, end: 1),
                duration: AppDurations.reduced,
                curve: AppCurves.out,
                builder: (context, t, child) => Opacity(
                  opacity: ((t - 0.6) / 0.4).clamp(0.0, 1.0),
                  child: Transform.scale(scale: t, child: child),
                ),
                child: widget.bar(width),
              ),
            ),
          ],
        );
      },
    );
  });
}
