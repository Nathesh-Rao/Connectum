import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// Press feedback for a list row that sits inside a padded list. The tint
/// runs edge to edge (it bleeds over the list's horizontal padding by
/// [bleed]) and for the row's full height, behind the content, so the content
/// itself never moves or changes width.
///
/// The tint follows the touch: it shows on press and clears on release, on
/// cancel, as soon as a long press fires (the menu takes over) and when
/// [resetKey] changes (the row was pinned, muted or re-sorted), so nothing
/// stays highlighted.
class AppRowHighlight extends StatefulWidget {
  const AppRowHighlight({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.bleed = AppSpacing.page,
    this.resetKey,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How far the tint reaches past the row on each side: the list's padding.
  final double bleed;
  final Object? resetKey;

  @override
  State<AppRowHighlight> createState() => _AppRowHighlightState();
}

class _AppRowHighlightState extends State<AppRowHighlight> {
  bool _isPressed = false;

  void _set(bool value) {
    if (_isPressed == value || !mounted) return;
    setState(() => _isPressed = value);
  }

  @override
  void didUpdateWidget(AppRowHighlight old) {
    super.didUpdateWidget(old);
    if (old.resetKey != widget.resetKey) _isPressed = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              widget.onLongPress!();
            },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -widget.bleed,
            right: -widget.bleed,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: AppDurations.fast,
                curve: AppCurves.out,
                color: _isPressed ? AppColors.primaryTint : Colors.transparent,
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}
