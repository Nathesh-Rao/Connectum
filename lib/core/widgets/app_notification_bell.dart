import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// The notification control: a white 30 dp bell circle, which grows into a
/// 36 dp accent tinted pill with the unread count at its right while the count is above
/// zero. The whole control is one tap area of at least 48 dp.
class AppNotificationBell extends StatefulWidget {
  const AppNotificationBell({
    super.key,
    required this.count,
    required this.onPressed,
  });

  final int count;
  final VoidCallback onPressed;

  @override
  State<AppNotificationBell> createState() => _AppNotificationBellState();
}

class _AppNotificationBellState extends State<AppNotificationBell>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 260);
  static const _pillPad = 3.0;
  static const _badgeGap = 4.0;
  static const _badgeEnd = 4.0;

  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: _duration,
    value: widget.count > 0 ? 1 : 0,
  );
  late final _size = CurvedAnimation(
    parent: _open,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final _pop = CurvedAnimation(
    parent: _open,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeIn,
  );

  // Kept while the pill closes, so the badge does not blank out mid-motion.
  late String _label = _labelOf(widget.count);

  static String _labelOf(int count) => count > 99 ? '99+' : '$count';

  @override
  void didUpdateWidget(AppNotificationBell old) {
    super.didUpdateWidget(old);
    if (widget.count > 0) _label = _labelOf(widget.count);
    final shouldOpen = widget.count > 0;
    if (shouldOpen == (old.count > 0)) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _open.value = shouldOpen ? 1 : 0;
    } else if (shouldOpen) {
      _open.forward();
    } else {
      _open.reverse();
    }
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isStill = MediaQuery.disableAnimationsOf(context);
    final semantic = widget.count > 0
        ? 'Notifications, ${widget.count} unread'
        : 'Notifications';
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSpacing.badgedIconHit,
            minHeight: AppSpacing.badgedIconHit,
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: AnimatedBuilder(
              animation: _open,
              builder: (context, _) {
                final t = _size.value.clamp(0.0, 1.0);
                return DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSpacing.bellPill),
                    border: Border.all(
                      color: Color.lerp(
                        Colors.transparent,
                        AppColors.primaryBorder,
                        t,
                      )!,
                    ),
                  ),
                  child: Container(
                    height: AppSpacing.bellPill,
                    padding: EdgeInsets.symmetric(horizontal: _pillPad * t),
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        Colors.transparent,
                        AppColors.primaryTint,
                        t,
                      ),
                      borderRadius: BorderRadius.circular(AppSpacing.bellPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const _BellCircle(),
                        if (!_open.isDismissed)
                          ClipRect(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: t,
                              heightFactor: 1,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: _badgeGap,
                                  right: _badgeEnd,
                                ),
                                child: Opacity(
                                  opacity: _pop.value.clamp(0.0, 1.0),
                                  child: Transform.scale(
                                    scale: _pop.value.clamp(0.0, 1.2),
                                    child: _CountBadge(
                                      label: _label,
                                      isStill: isStill,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BellCircle extends StatelessWidget {
  const _BellCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.bellCircle,
      height: AppSpacing.bellCircle,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: const Icon(
        Icons.notifications_none,
        size: 16,
        color: AppColors.ink,
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label, required this.isStill});

  final String label;
  final bool isStill;

  @override
  Widget build(BuildContext context) {
    final isWide = label.length > 2;
    return Container(
      width: isWide ? null : AppSpacing.bellBadge,
      height: AppSpacing.bellBadge,
      constraints: const BoxConstraints(minWidth: AppSpacing.bellBadge),
      padding: EdgeInsets.symmetric(horizontal: isWide ? 5 : 0),
      decoration: BoxDecoration(
        color: AppColors.primaryBright,
        borderRadius: BorderRadius.circular(AppSpacing.bellBadge),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: AnimatedSwitcher(
          duration: isStill ? Duration.zero : const Duration(milliseconds: 190),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            label,
            key: ValueKey(label),
            maxLines: 1,
            style: AppText.bellCount,
          ),
        ),
      ),
    );
  }
}
