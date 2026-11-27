import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_sv.dart';
import '../theme/app_tones.dart';
import 'app_fab.dart';

/// One bubble of an [AppSpeedDial].
class AppSpeedDialOption {
  const AppSpeedDialOption({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.tone = AppTones.primary,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final AppTone tone;
}

/// A floating button that fans [options] out above it. Tap: the button's
/// grid icon cross-fades to a cross, a light scrim fades in and the options fly up
/// one after the other, each as a round tinted icon with a white label to its
/// left. Tap an option, the scrim or Back to close. With one option the
/// button shows its icon and runs it at once; with none nothing is drawn.
///
/// Fill the area the button floats in (a `Positioned.fill` in a `Stack`):
/// the widget only catches taps on the button, and on everything while open.
/// A change of [closeKey] closes it (the tab or the view changed).
class AppSpeedDial extends StatefulWidget {
  const AppSpeedDial({
    super.key,
    required this.options,
    this.closeKey,
    this.semanticLabel = 'Actions',
    this.buttonKey,
  });

  final List<AppSpeedDialOption> options;
  final Object? closeKey;
  final String semanticLabel;

  /// Put on the round button (a first-run tour points at it).
  final GlobalKey? buttonKey;

  @override
  State<AppSpeedDial> createState() => _AppSpeedDialState();
}

class _AppSpeedDialState extends State<AppSpeedDial>
    with SingleTickerProviderStateMixin {
  static const _head = 220;
  static const _flight = 260;

  late AnimationController _anim;
  bool _isOpen = false;

  int get _count => widget.options.length;

  Duration _durationFor(int n) => Duration(
    milliseconds: _flight + (math.max(n, 1) - 1) * AppSv.dialStagger.round(),
  );

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: _durationFor(_count));
  }

  @override
  void didUpdateWidget(AppSpeedDial old) {
    super.didUpdateWidget(old);
    if (old.options.length != _count) {
      _anim.duration = _durationFor(_count);
    }
    if (_count < 2 && _isOpen) {
      _set(false);
    } else if (old.closeKey != widget.closeKey && _isOpen) {
      _set(false);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _set(bool value) {
    if (_isOpen == value) return;
    setState(() => _isOpen = value);
    if (value) {
      _anim.forward();
    } else {
      _anim.reverse();
    }
  }

  void _pick(AppSpeedDialOption o) {
    _set(false);
    o.onSelected();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    if (options.isEmpty) return const SizedBox.shrink();
    if (options.length == 1) {
      final only = options.first;
      return Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.fabMargin),
          child: AppFab(
            key: widget.buttonKey,
            semanticLabel: only.label,
            onPressed: only.onSelected,
            child: Icon(only.icon, color: AppColors.white),
          ),
        ),
      );
    }
    final total = _durationFor(options.length).inMilliseconds;
    final head = _head / total;
    return PopScope(
      canPop: !_isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _set(false);
      },
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final base = CurvedAnimation(
            parent: _anim,
            curve: Interval(0, head, curve: AppCurves.out),
          ).value;
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_isOpen,
                  child: Semantics(
                    button: true,
                    label: 'Close menu',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _set(false),
                      child: ColoredBox(
                        color: AppSv.dialScrim.withValues(
                          alpha: AppSv.dialScrim.a * base,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: AppSpacing.fabMargin,
                bottom: AppSpacing.fabMargin,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = options.length - 1; i >= 0; i--)
                      _Bubble(
                        option: options[i],
                        t: _flightOf(i, total),
                        isEnabled: _isOpen,
                        onTap: () => _pick(options[i]),
                      ),
                    AppFab(
                      key: widget.buttonKey,
                      semanticLabel: _isOpen
                          ? 'Close menu'
                          : widget.semanticLabel,
                      onPressed: () => _set(!_isOpen),
                      child: AnimatedSwitcher(
                        duration: AppDurations.sheetResize,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: RotationTransition(
                            turns: Tween<double>(
                              begin: 0.125,
                              end: 0,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: Icon(
                          _isOpen ? Icons.close : Icons.grid_view_rounded,
                          key: ValueKey(_isOpen),
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 0..1 progress of option [i] (0 is the one next to the button).
  double _flightOf(int i, int total) {
    final start = i * AppSv.dialStagger / total;
    final end = math.min(1.0, start + _flight / total);
    final raw = ((_anim.value - start) / (end - start)).clamp(0.0, 1.0);
    return raw;
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.option,
    required this.t,
    required this.isEnabled,
    required this.onTap,
  });

  final AppSpeedDialOption option;
  final double t;
  final bool isEnabled;
  final VoidCallback onTap;

  static const _lift = 16.0;

  @override
  Widget build(BuildContext context) {
    if (t <= 0) return const SizedBox.shrink();
    final eased = Curves.easeOutBack.transform(t).clamp(0.0, 1.08);
    final opacity = Curves.easeOut.transform(t).clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, (1 - eased) * _lift),
        child: Transform.scale(
          scale: 0.6 + 0.4 * eased,
          alignment: Alignment.centerRight,
          child: IgnorePointer(
            ignoring: !isEnabled,
            child: Padding(
              padding: const EdgeInsets.only(
                bottom: AppSv.dialGap,
                right: (AppSpacing.fab - AppSv.dialOption) / 2,
              ),
              child: Semantics(
                button: true,
                label: option.label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: AppRadius.pillAll,
                          boxShadow: AppSv.dialShadow,
                        ),
                        child: Text(option.label, style: AppSv.dialLabel),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        width: AppSv.dialOption,
                        height: AppSv.dialOption,
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            option.tone.solid.withValues(alpha: 0.14),
                            AppColors.white,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: AppSv.dialShadow,
                        ),
                        child: Icon(
                          option.icon,
                          size: 22,
                          color: option.tone.solid,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
