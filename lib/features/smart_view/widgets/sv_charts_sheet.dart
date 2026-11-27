import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../../../data/smart_view/engine/sv_insights.dart';
import '../../../data/smart_view/sv_columns.dart';
import '../../../data/smart_view/sv_query.dart';
import '../smart_view_controller.dart';
import 'sv_chart_view.dart';
import 'sv_col_icon.dart';
import 'sv_insight_sheet.dart';
import 'sv_pill.dart';

/// The Charts sheet: bar, donut or line over the rows that pass the search
/// and filters, grouped by a status, choice, yes/no or date field and counted,
/// summed or averaged.
class SvChartsSheet {
  SvChartsSheet._();

  static Future<void> show(BuildContext context, SmartViewController c) {
    return SvInsightSheet.show(
      context,
      title: 'Charts',
      icon: Icons.bar_chart_rounded,
      tone: AppTones.violet,
      body: SvChartsBody(controller: c),
    );
  }
}

class SvChartsBody extends StatefulWidget {
  const SvChartsBody({super.key, required this.controller});

  final SmartViewController controller;

  @override
  State<SvChartsBody> createState() => _SvChartsBodyState();
}

class _SvChartsBodyState extends State<SvChartsBody> {
  SvChartSpec? _spec;
  SvChartKind? _kind;

  SvChartSpec _initial(SvEngineInput input) {
    final cols = input.groupColumns;
    final own = cols.where(
      (c) =>
          !c.isMeta &&
          (c.type == SvColType.status || c.type == SvColType.select),
    );
    final status = input.statusKey;
    final first = own.isNotEmpty
        ? own.first
        : cols.where((c) => c.key == status).firstOrNull ?? cols.first;
    return SvChartSpec(groupKey: first.key);
  }

  void _setGroup(SvEngineInput input, String key) => setState(() {
    final spec = _spec!;
    _spec = SvChartSpec(groupKey: key, agg: spec.agg, valueKey: spec.valueKey);
    if (_kind == SvChartKind.line && !input.isDate(key)) {
      _kind = SvChartKind.bar;
    } else if (input.isDate(key) && _kind == SvChartKind.donut) {
      _kind = SvChartKind.bar;
    }
  });

  void _setKind(SvEngineInput input, SvChartKind kind) => setState(() {
    _kind = kind;
    if (kind == SvChartKind.line && !input.isDate(_spec!.groupKey)) {
      final dates = input.groupColumns.where((c) => input.isDate(c.key));
      final date =
          dates.where((c) => !c.isMeta).firstOrNull ?? dates.firstOrNull;
      if (date != null) {
        _spec = SvChartSpec(
          groupKey: date.key,
          agg: _spec!.agg,
          valueKey: _spec!.valueKey,
        );
      }
    }
  });

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Obx(() {
      final input = c.engineInput;
      if (input == null) return const SizedBox.shrink();
      final rows = c.insightRows;
      final loaded = input.rows.length;
      final groups = input.groupColumns;
      final note = SvInsightNote(
        shown: rows.length,
        loaded: loaded,
        hasMore: c.hasMorePages,
      );
      if (loaded == 0 || groups.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            note,
            const SvInsightEmpty(
              icon: Icons.bar_chart_rounded,
              title: 'Nothing to chart yet',
              caption: 'Charts show up when there are records',
            ),
          ],
        );
      }
      if (_spec == null || input.col(_spec!.groupKey) == null) {
        _spec = _initial(input);
        _kind = null;
      }
      final spec = _spec!;
      final data = SvInsights.chart(input.table, rows, spec);
      final kind = _kind ?? SvInsights.defaultKind(data);
      final hasDate = groups.any((g) => input.isDate(g.key));
      final group = input.col(spec.groupKey);
      final measures = input.measureKeys;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          note,
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final k in SvChartKind.values)
                if (k != SvChartKind.line || hasDate)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: _KindChip(
                      kind: k,
                      isSelected: k == kind,
                      onTap: () => _setKind(input, k),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              Builder(
                builder: (anchor) => SvPill(
                  label: 'Group by: ${group?.label ?? ''}',
                  maxWidth: 220,
                  onTap: () => AppPopupMenuCard.show(anchor, [
                    for (final g in groups)
                      AppMenuItem(
                        icon: g.key == spec.groupKey
                            ? Icons.check
                            : SvColIcon.of(g.type),
                        label: g.label,
                        onTap: () => _setGroup(input, g.key),
                      ),
                  ]),
                ),
              ),
              Builder(
                builder: (anchor) => SvPill(
                  label: 'Value: ${_valueLabel(input, spec)}',
                  maxWidth: 240,
                  onTap: () => AppPopupMenuCard.show(anchor, [
                    AppMenuItem(
                      icon: spec.valueKey == null ? Icons.check : Icons.tag,
                      label: 'Count',
                      onTap: () => setState(
                        () => _spec = SvChartSpec(groupKey: spec.groupKey),
                      ),
                    ),
                    for (final m in measures)
                      for (final a in const [SvChartAgg.sum, SvChartAgg.avg])
                        AppMenuItem(
                          icon: spec.valueKey == m && spec.agg == a
                              ? Icons.check
                              : Icons.functions,
                          label:
                              '${a == SvChartAgg.sum ? 'Sum' : 'Average'} of ${input.col(m)?.label}',
                          onTap: () => setState(
                            () => _spec = SvChartSpec(
                              groupKey: spec.groupKey,
                              agg: a,
                              valueKey: m,
                            ),
                          ),
                        ),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (data.isEmpty)
            const SvInsightEmpty(
              icon: Icons.bar_chart_rounded,
              title: 'Nothing to chart',
              caption: 'No record matches the search and filters',
            )
          else ...[
            Text(data.subtitle, style: AppText.bodyStrong),
            const SizedBox(height: AppSpacing.sm),
            SvChartView(
              key: const ValueKey('sv-chart'),
              data: data,
              kind: kind,
            ),
            if (data.omitted > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  '${data.omitted} earlier ${data.omitted == 1 ? 'period is' : 'periods are'} not shown',
                  style: AppText.supporting,
                ),
              ),
          ],
        ],
      );
    });
  }

  static String _valueLabel(SvEngineInput input, SvChartSpec spec) {
    final key = spec.valueKey;
    if (key == null) return 'Count';
    final label = input.col(key)?.label ?? key;
    return '${spec.agg == SvChartAgg.sum ? 'Sum' : 'Average'} of $label';
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.kind,
    required this.isSelected,
    required this.onTap,
  });

  final SvChartKind kind;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (kind) {
      SvChartKind.bar => ('Bar', Icons.bar_chart_rounded),
      SvChartKind.donut => ('Donut', Icons.donut_large_rounded),
      SvChartKind.line => ('Line', Icons.show_chart_rounded),
    };
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label chart',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.smartChip,
          height: AppSpacing.chipHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.violetTint : AppColors.fill,
            borderRadius: AppRadius.pillAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? AppColors.violetStrong : AppColors.muted,
              ),
              const SizedBox(width: AppSpacing.xxs + 2),
              Text(
                label,
                style: AppText.buttonSmall.copyWith(
                  color: isSelected ? AppColors.violetStrong : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
