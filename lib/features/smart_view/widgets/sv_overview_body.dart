import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/widgets/app_refresh.dart';
import '../../../data/smart_view/models/sv_source.dart';
import '../../../data/smart_view/overview/sv_overview.dart';
import '../models/sv_overview_model.dart';
import 'sv_kpi_sheet.dart';
import 'sv_overview_card.dart';
import 'sv_stagger_in.dart';

/// The Overview page: a line of what it is and when it was read, four KPI
/// tiles, then a card per structure. Pull to refresh reads everything again.
class SvOverviewBody extends StatelessWidget {
  const SvOverviewBody({
    super.key,
    required this.model,
    required this.isEmpty,
    required this.onOpen,
    required this.onRefresh,
    this.scroll,
  });

  final SvOverviewModel model;

  /// The person has no structure to open.
  final bool isEmpty;
  final void Function(SvSource source) onOpen;
  final Future<void> Function() onRefresh;
  final ScrollController? scroll;

  static const subtitle = 'Your structures and data at a glance';
  static const emptyTitle = 'No smart views yet';
  static const partialNote = 'Based on loaded records';

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return AppRefresh(
      onRefresh: onRefresh,
      controller: scroll,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xxs,
            AppSpacing.md,
            AppSpacing.lg + bottom,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _Caption(model: model),
              const SizedBox(height: AppSpacing.sm),
              if (isEmpty)
                const _Empty()
              else ...[
                _Tiles(model: model),
                _PartialNote(model: model),
                const SizedBox(height: AppSpacing.sm),
                _Cards(model: model, onOpen: onOpen),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.model});

  final SvOverviewModel model;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final at = model.updatedAt.value;
      final line = at == null
          ? (model.isRunning.value ? 'Updating…' : '')
          : 'Updated ${SvOverview.age(at.millisecondsSinceEpoch, model.clock())}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(SvOverviewBody.subtitle, style: AppText.readable),
          if (line.isNotEmpty) Text(line, style: AppText.caption),
        ],
      );
    });
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(
        child: Text(SvOverviewBody.emptyTitle, style: AppText.subtitle),
      ),
    );
  }
}

class _PartialNote extends StatelessWidget {
  const _PartialNote({required this.model});

  final SvOverviewModel model;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final show = model.cards.isNotEmpty && model.isSettled && model.isPartial;
      if (!show) return const SizedBox.shrink();
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xs),
        child: Text(SvOverviewBody.partialNote, style: AppText.caption),
      );
    });
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.model});

  final SvOverviewModel model;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final has = model.cards.isNotEmpty;
      final settled = has && model.isSettled;
      final tiles = [
        _Tile(
          label: 'Structures',
          icon: Icons.dynamic_form_outlined,
          tone: AppTones.blue,
          value: has ? model.structures : null,
        ),
        _Tile(
          label: 'Records',
          icon: Icons.table_rows_outlined,
          tone: AppTones.violet,
          value: settled ? model.records : null,
        ),
        _Tile(
          label: 'This week',
          icon: Icons.calendar_today_outlined,
          tone: AppTones.teal,
          value: settled ? model.week : null,
        ),
        if (model.hasPendingSource)
          _Tile(
            label: 'Waiting for approval',
            icon: Icons.hourglass_empty_rounded,
            tone: AppTones.purple,
            value: settled ? model.pending : null,
          ),
      ];
      return SvUniformGrid(
        gap: AppSpacing.sm,
        children: [
          for (var i = 0; i < tiles.length; i++)
            SvStaggerIn(index: i, child: tiles[i]),
        ],
      );
    });
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.icon,
    required this.tone,
    required this.value,
  });

  final String label;
  final IconData icon;
  final AppTone tone;

  /// Null shows "…" until the number is known.
  final int? value;

  @override
  Widget build(BuildContext context) {
    final isAnimated = !MediaQuery.disableAnimationsOf(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSv.ovTileRadius),
        border: Border.all(color: AppSv.cardBorder),
        boxShadow: AppSv.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSv.ovIconCircle,
            height: AppSv.ovIconCircle,
            decoration: BoxDecoration(color: tone.tint, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: tone.strong),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(label, style: AppSv.ovLabel),
          const SizedBox(height: AppSpacing.xxs),
          if (value == null)
            const Text('…', style: AppSv.ovValue)
          else
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value!.toDouble()),
              duration: isAnimated ? AppSv.ovCount : Duration.zero,
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                SvOverview.thousands(v.round()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppSv.ovValue,
              ),
            ),
        ],
      ),
    );
  }
}

class _Cards extends StatelessWidget {
  const _Cards({required this.model, required this.onOpen});

  final SvOverviewModel model;
  final void Function(SvSource source) onOpen;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final cards = model.cards.toList();
      if (cards.isEmpty) {
        return Column(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSv.cardGap),
                child: SvOverviewCardView(
                  key: ValueKey('sv-ov-wait-$i'),
                  card: SvOverviewCard(const SvSource(name: '…', caption: '…')),
                  clock: model.clock,
                  onOpen: () {},
                  onRetry: () {},
                ),
              ),
          ],
        );
      }
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSv.cardGap),
              child: SvStaggerIn(
                key: ValueKey('sv-ov-${cards[i].source.name}'),
                index: i + 4 > 10 ? 10 : i + 4,
                child: SvOverviewCardView(
                  card: cards[i],
                  clock: model.clock,
                  onOpen: () => onOpen(cards[i].source),
                  onRetry: () => model.retry(cards[i]),
                ),
              ),
            ),
        ],
      );
    });
  }
}
