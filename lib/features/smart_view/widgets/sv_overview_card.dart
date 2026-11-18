import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/smart_view/overview/sv_overview.dart';
import '../models/sv_overview_model.dart';

/// One structure on the Overview: name and fields, the big count with the
/// seven-day bars, the status mix and when the last record came. Its own
/// phase decides what it shows: a skeleton, the numbers or a retry line.
class SvOverviewCardView extends StatelessWidget {
  const SvOverviewCardView({
    super.key,
    required this.card,
    required this.clock,
    required this.onOpen,
    required this.onRetry,
  });

  final SvOverviewCard card;
  final DateTime Function() clock;
  final VoidCallback onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final phase = card.phase.value;
      final stats = card.stats.value;
      return switch (phase) {
        SvCardPhase.loading => _Shell(card: card, child: const _Skeleton()),
        SvCardPhase.error => _Shell(
          card: card,
          child: _Failed(onRetry: onRetry),
        ),
        SvCardPhase.ready => _Shell(
          card: card,
          onTap: onOpen,
          child: _Numbers(stats: stats!, clock: clock),
        ),
      };
    });
  }
}

class _Shell extends StatefulWidget {
  const _Shell({required this.card, required this.child, this.onTap});

  final SvOverviewCard card;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  bool _isDown = false;

  void _set(bool v) {
    if (_isDown != v && mounted) setState(() => _isDown = v);
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.card.source;
    final n = source.fields.length;
    final isOpen = widget.onTap != null;
    return Semantics(
      button: isOpen,
      label: '${source.caption}: open as a table',
      container: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: isOpen ? (_) => _set(true) : null,
        onTapUp: isOpen ? (_) => _set(false) : null,
        onTapCancel: isOpen ? () => _set(false) : null,
        child: AnimatedScale(
          scale: _isDown ? AppSv.ovPressScale : 1,
          duration: AppSv.ovPress,
          child: Container(
            padding: const EdgeInsets.all(AppSv.ovPad),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppSv.cardRadius),
              border: Border.all(color: AppSv.cardBorder),
              boxShadow: AppSv.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: AppSv.ovCardIcon,
                      height: AppSv.ovCardIcon,
                      decoration: BoxDecoration(
                        color: AppTones.violet.tint,
                        borderRadius: BorderRadius.circular(
                          AppSv.ovCardIconRadius,
                        ),
                      ),
                      child: Icon(
                        Icons.dynamic_form_outlined,
                        size: 20,
                        color: AppTones.violet.strong,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppSv.ovName,
                          ),
                          Text(
                            n == 1 ? '1 field' : '$n fields',
                            style: AppSv.ovLabel,
                          ),
                        ],
                      ),
                    ),
                    if (isOpen)
                      const Icon(
                        Icons.chevron_right,
                        size: 22,
                        color: AppColors.rowChevron,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                widget.child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Numbers extends StatelessWidget {
  const _Numbers({required this.stats, required this.clock});

  final SvOverviewStats stats;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) {
    final count = stats.count;
    final names = [for (final m in stats.mix) m.label]..sort();
    Color colorOf(String label) =>
        AppSv.chartPalette[names.indexOf(label) % AppSv.chartPalette.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    SvOverview.thousands(count),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppSv.ovBig,
                  ),
                  Text(count == 1 ? 'record' : 'records', style: AppSv.ovLabel),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SvSparkline(buckets: stats.buckets),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (stats.mix.isEmpty)
          const Text('Nothing recorded yet', style: AppSv.ovLabel)
        else ...[
          _MixBar(mix: stats.mix, colorOf: colorOf),
          const SizedBox(height: AppSpacing.xs),
          _Legend(mix: stats.mix, colorOf: colorOf),
        ],
        const SizedBox(height: AppSpacing.sm),
        const Divider(height: 1, thickness: 1, color: AppSv.hairline),
        const SizedBox(height: AppSpacing.xs),
        Text(SvOverview.lastEntry(stats.lastTs, clock()), style: AppSv.ovLabel),
      ],
    );
  }
}

/// Seven bars, one per day, today last in the primary colour.
class SvSparkline extends StatelessWidget {
  const SvSparkline({super.key, required this.buckets});

  final List<int> buckets;

  @override
  Widget build(BuildContext context) {
    final top = buckets.fold(0, (a, b) => b > a ? b : a);
    return Semantics(
      label: 'Records in the last seven days: ${buckets.join(', ')}',
      excludeSemantics: true,
      child: SizedBox(
        height: AppSv.ovBarMax,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < buckets.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSv.ovBarGap),
              Container(
                width: AppSv.ovBarWidth,
                height: buckets[i] == 0 || top == 0
                    ? AppSv.ovBarDash
                    : (AppSv.ovBarMax * buckets[i] / top).clamp(
                        AppSv.ovBarDash * 2,
                        AppSv.ovBarMax,
                      ),
                decoration: BoxDecoration(
                  color: i == buckets.length - 1
                      ? AppColors.primary
                      : AppColors.primary.withValues(
                          alpha: AppSv.ovBarRestAlpha,
                        ),
                  borderRadius: BorderRadius.circular(AppSv.ovBarWidth / 2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MixBar extends StatelessWidget {
  const _MixBar({required this.mix, required this.colorOf});

  final List<SvStatusCount> mix;
  final Color Function(String label) colorOf;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSv.ovMixHeight,
      child: Row(
        children: [
          for (var i = 0; i < mix.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSv.ovMixGap),
            Expanded(
              flex: mix[i].count,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorOf(mix[i].label),
                  borderRadius: BorderRadius.circular(AppSv.ovMixRadius),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.mix, required this.colorOf});

  final List<SvStatusCount> mix;
  final Color Function(String label) colorOf;

  @override
  Widget build(BuildContext context) {
    final shown = mix.take(AppSv.ovLegendMax).toList();
    final more = mix.length - shown.length;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: [
        for (final m in shown)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: AppSv.pillDot,
                height: AppSv.pillDot,
                decoration: BoxDecoration(
                  color: colorOf(m.label),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  m.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppSv.ovLegend,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(SvOverview.thousands(m.count), style: AppSv.ovLegendCount),
            ],
          ),
        if (more > 0) Text('+$more more', style: AppSv.ovLegend),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Text("Couldn't load", style: AppText.readable)),
        AppButton.text(label: 'Retry', onPressed: onRetry),
      ],
    );
  }
}

/// Grey blocks in the shape of the numbers, pulsing in alpha (no gradient).
class _Skeleton extends StatefulWidget {
  const _Skeleton();

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: AppSv.ovPulse,
  );
  bool _isStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isStarted) return;
    _isStarted = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _anim.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Widget _block(double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: AppSv.sortIconFill,
      borderRadius: AppRadius.pillAll,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: FadeTransition(
        key: const ValueKey('sv-overview-skeleton'),
        opacity: Tween<double>(
          begin: AppSv.ovSkeletonLow,
          end: 1,
        ).animate(_anim),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _block(88, 28),
                const Spacer(),
                _block(66, AppSv.ovBarMax),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _block(double.infinity, AppSv.ovMixHeight),
            const SizedBox(height: AppSpacing.sm),
            _block(120, 12),
          ],
        ),
      ),
    );
  }
}
