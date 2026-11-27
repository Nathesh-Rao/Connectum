import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../selection/message_selection.dart';
import 'package:connectum/core/theme/theme.dart';
import 'swipe_to_reply.dart';

/// Wraps one message row of a thread: a tinted band across the full width
/// while it is selected, and while anything is selected a tap adds or removes
/// the row (the row's own taps are off, as in WhatsApp).
class SelectableRow extends StatelessWidget {
  const SelectableRow({
    super.key,
    required this.selection,
    required this.id,
    required this.child,
    this.bleed = AppSpacing.lg,
    this.onSwipeReply,
    this.swipeKey,
  });

  final MessageSelection selection;
  final String id;
  final Widget child;

  /// How far the band reaches past the row on each side: the list's padding.
  final double bleed;

  /// Starts a reply to this row's message; null when it cannot be replied to
  /// (the row then does not move). Off while anything is selected.
  final VoidCallback? onSwipeReply;

  /// Lets the first-run tour slide this row (see `SwipeToReplyState.peek`).
  final GlobalKey<SwipeToReplyState>? swipeKey;

  @override
  Widget build(BuildContext context) => Obx(() {
    final isSelected = selection.isSelected(id);
    final isActive = selection.isActive;
    final content = onSwipeReply == null
        ? child
        : SwipeToReply(
            key: swipeKey,
            onReply: onSwipeReply,
            isEnabled: !isActive,
            child: child,
          );
    final row = Stack(
      clipBehavior: Clip.none,
      children: [
        PositionedDirectional(
          start: -bleed,
          end: -bleed,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: AppDurations.reduced,
              opacity: isSelected ? 1 : 0,
              child: const ColoredBox(color: AppColors.selectionTint),
            ),
          ),
        ),
        isActive ? IgnorePointer(child: content) : content,
      ],
    );
    return Semantics(
      selected: isSelected,
      child: KeyedSubtree(
        key: selection.anchorOf(id),
        child: isActive
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => selection.onTap(id),
                onLongPress: () => selection.onLongPress(id),
                child: row,
              )
            : row,
      ),
    );
  });
}
