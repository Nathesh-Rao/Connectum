import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../theme/app_tones.dart';
import 'app_form_card.dart';

// TUNE ME: primary action style
/// True: the first action is solid orange with white content (the old look).
/// False: a peach tint with strong orange content and a soft border.
const kSolidPrimaryAction = false;

/// One thing to offer: [id] is what [AppActionBar.onTap] gets back.
class ActionItem {
  const ActionItem({
    required this.id,
    required this.label,
    required this.icon,
    this.tone = AppTones.slate,
  });

  final String id;
  final String label;
  final IconData icon;
  final AppTone tone;
}

enum AppActionLayout {
  /// For a card: the first [AppActionBar.maxVisible] side by side, the rest
  /// behind "More actions".
  row,

  /// For a screen: the first one full width, the rest in two columns.
  full,
}

/// The actions of a record as buttons. The first is the primary (a stronger
/// peach tint, or solid with [kSolidPrimaryAction]), the others are subtle
/// tints of their tone. Rows are one line with an ellipsis and
/// grow with the text scale. On a card the actions past [maxVisible] sit in a
/// two-column grid, the same one the details screen shows, folded behind a
/// slim chevron bar at the bottom.
class AppActionBar extends StatefulWidget {
  const AppActionBar({
    super.key,
    required this.items,
    required this.onTap,
    this.maxVisible = 2,
    this.isExpandable = true,
    this.layout = AppActionLayout.row,
    this.isEnabled = true,
    this.inset = 0,
  });

  static const buttonHeight = 44.0;
  static const barHeight = 40.0;
  static const barHit = 48.0;
  static const moreLabel = 'More actions';
  static const _gap = AppSpacing.xs;
  static const _iconSize = 18.0;

  final List<ActionItem> items;
  final ValueChanged<ActionItem> onTap;
  final int maxVisible;

  /// False: every action is shown, none hides behind the bar.
  final bool isExpandable;
  final AppActionLayout layout;
  final bool isEnabled;

  /// Side space of the buttons. The expand bar always spans the full width,
  /// so a card can run it edge to edge.
  final double inset;

  @override
  State<AppActionBar> createState() => _AppActionBarState();
}

class _AppActionBarState extends State<AppActionBar> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final side = EdgeInsets.symmetric(horizontal: widget.inset);
    if (widget.layout == AppActionLayout.full) {
      return Padding(padding: side, child: _full(items));
    }
    final visible = widget.isExpandable
        ? widget.maxVisible.clamp(1, items.length)
        : items.length;
    final head = items.take(visible).toList();
    final rest = items.skip(visible).toList();
    final scope = AppFormCardScope.maybeOf(context);
    final isMotionOff = MediaQuery.disableAnimationsOf(context);
    final duration = isMotionOff ? Duration.zero : AppDurations.fast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: side,
          child: Row(
            children: [
              for (var i = 0; i < head.length; i++) ...[
                if (i > 0) const SizedBox(width: AppActionBar._gap),
                Expanded(child: _button(head[i], isPrimary: i == 0)),
              ],
            ],
          ),
        ),
        if (rest.isNotEmpty)
          _Folded(
            isMotionOff: isMotionOff,
            duration: duration,
            child: _isOpen
                ? Padding(
                    padding: side.copyWith(top: AppActionBar._gap),
                    child: _TintedGrid(
                      items: rest,
                      onTap: widget.isEnabled ? widget.onTap : null,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        if (scope?.line != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppFormCardActionArea.inset,
              AppSpacing.xs,
              AppFormCardActionArea.inset,
              0,
            ),
            child: scope!.line,
          ),
        if (rest.isNotEmpty || scope != null)
          _ExpandBar(
            isOpen: _isOpen,
            duration: duration,
            scope: scope,
            onTap: rest.isEmpty
                ? null
                : () => setState(() => _isOpen = !_isOpen),
          ),
      ],
    );
  }

  Widget _full(List<ActionItem> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _button(items.first),
      if (items.length > 1) ...[
        const SizedBox(height: AppActionBar._gap),
        _TintedGrid(
          items: items.skip(1).toList(),
          onTap: widget.isEnabled ? widget.onTap : null,
        ),
      ],
    ],
  );

  Widget _button(ActionItem item, {bool isPrimary = true}) => _ActionButton(
    item: item,
    isPrimary: isPrimary,
    onTap: widget.isEnabled ? () => widget.onTap(item) : null,
  );
}

/// Animates the height of [child]. With motion off it does not animate at
/// all: an [AnimatedSize] with a zero duration asserts in layout.
class _Folded extends StatelessWidget {
  const _Folded({
    required this.isMotionOff,
    required this.duration,
    required this.child,
  });

  final bool isMotionOff;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => isMotionOff
      ? child
      : AnimatedSize(
          duration: duration,
          curve: AppCurves.out,
          alignment: Alignment.topCenter,
          child: child,
        );
}

/// The tinted buttons in two columns (an odd last one runs full width): the
/// one grid of the details screen and of an opened card.
class _TintedGrid extends StatelessWidget {
  const _TintedGrid({required this.items, required this.onTap});

  final List<ActionItem> items;
  final ValueChanged<ActionItem>? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final half = (box.maxWidth - AppActionBar._gap) / 2;
        return Wrap(
          spacing: AppActionBar._gap,
          runSpacing: AppActionBar._gap,
          children: [
            for (var i = 0; i < items.length; i++)
              SizedBox(
                width: items.length.isOdd && i == items.length - 1
                    ? box.maxWidth
                    : half,
                child: _ActionButton(
                  item: items[i],
                  isPrimary: false,
                  onTap: onTap == null ? null : () => onTap!(items[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.item,
    required this.isPrimary,
    required this.onTap,
  });

  final ActionItem item;
  final bool isPrimary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isOff = onTap == null;
    final isSolid = isPrimary && kSolidPrimaryAction;
    final isSoft = isPrimary && !kSolidPrimaryAction;
    final fill = isSolid
        ? AppColors.accent
        : isSoft
        ? AppTones.primary.tint
        : item.tone.tint;
    final ink = isSolid
        ? AppColors.background
        : isSoft
        ? AppTones.primary.strong
        : item.tone.strong;
    return Semantics(
      button: true,
      enabled: !isOff,
      label: item.label,
      excludeSemantics: true,
      child: Opacity(
        opacity: isOff ? 0.5 : 1,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.controlAll,
            side: isSoft
                ? BorderSide(color: AppColors.accent.withValues(alpha: 0.35))
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppActionBar.buttonHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.icon, size: AppActionBar._iconSize, color: ink),
                    const SizedBox(width: AppSpacing.xxs),
                    Flexible(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.buttonSmall.copyWith(
                          color: ink,
                          fontWeight: isPrimary ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bottom strip of a card: a hairline, a tinted surface, the chevron
/// centred and, on a card, the time (and ticks) at the right. Without
/// [onTap] it is only the time. The whole 48 dp (the strip and the space above
/// it) is the tap target; the card's own clip rounds its corners.
class _ExpandBar extends StatelessWidget {
  const _ExpandBar({
    required this.isOpen,
    required this.duration,
    required this.scope,
    required this.onTap,
  });

  final bool isOpen;
  final Duration duration;
  final AppFormCardScope? scope;
  final VoidCallback? onTap;

  static const _lead = AppActionBar.barHit - AppActionBar.barHeight - _hairline;
  static const _hairline = 1.0;

  @override
  Widget build(BuildContext context) {
    final isTappable = onTap != null;
    final label = scope == null
        ? AppActionBar.moreLabel
        : '${AppActionBar.moreLabel}, ${scope!.timeLabel}';
    Widget content = Stack(
      alignment: Alignment.center,
      children: [
        if (isTappable)
          AnimatedRotation(
            turns: isOpen ? 0.5 : 0,
            duration: duration,
            curve: AppCurves.out,
            child: const Icon(
              Icons.keyboard_arrow_down,
              size: 22,
              color: AppColors.cardMuted,
            ),
          ),
        if (scope != null)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: scope!.stamp,
            ),
          ),
      ],
    );
    content = Material(
      color: AppColors.cardChip,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppActionBar.barHeight),
          child: content,
        ),
      ),
    );
    final bar = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: _lead),
        const Divider(height: _hairline, color: AppColors.cardLine),
        content,
      ],
    );
    if (!isTappable) {
      return Semantics(label: scope?.timeLabel, child: bar);
    }
    return Semantics(
      button: true,
      expanded: isOpen,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: AppActionBar.moreLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: bar,
        ),
      ),
    );
  }
}
