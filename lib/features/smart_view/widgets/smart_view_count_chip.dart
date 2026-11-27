import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import '../../../data/smart_view/engine/sv_insights.dart';

/// The record count in the view's header: "Total 120", or, while a search or
/// filter is on, "Showing 3 of 120". Never wraps; the title gives way first.
class SmartViewCountChip extends StatelessWidget {
  const SmartViewCountChip({super.key, required this.total, this.shown});

  final int total;

  /// Set while a search or filter is active.
  final int? shown;

  static const _swap = Duration(milliseconds: 180);

  bool get _isFiltered => shown != null;

  @override
  Widget build(BuildContext context) {
    final totalText = SvInsights.format(total);
    final shownText = _isFiltered ? SvInsights.format(shown!) : totalText;
    final label = _isFiltered
        ? 'Showing $shownText of $totalText records'
        : 'Total records $totalText';
    const muted = TextStyle(
      fontFamily: AppText.fontFamily,
      fontSize: AppText.sizeReadable,
      fontWeight: FontWeight.w500,
      height: AppText.heightControl,
      color: AppColors.muted,
    );
    final strong = muted.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.primaryStrong,
    );
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: const BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: AppRadius.pillAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_isFiltered ? 'Showing' : 'Total', style: muted, maxLines: 1),
            const SizedBox(width: AppSpacing.xxs),
            AnimatedSwitcher(
              duration: _swap,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.4),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                shownText,
                key: ValueKey(shownText),
                style: strong,
                maxLines: 1,
              ),
            ),
            if (_isFiltered) ...[
              const SizedBox(width: AppSpacing.xxs),
              Text('of $totalText', style: muted, maxLines: 1),
            ],
          ],
        ),
      ),
    );
  }
}
