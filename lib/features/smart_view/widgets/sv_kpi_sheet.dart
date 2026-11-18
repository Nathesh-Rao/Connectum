import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_tones.dart';
import '../../../data/smart_view/engine/sv_insights.dart';
import '../smart_view_controller.dart';
import 'sv_insight_sheet.dart';

/// The KPI sheet: a two-column grid of tiles over the rows that pass the
/// search and filters.
class SvKpiSheet {
  SvKpiSheet._();

  static Future<void> show(BuildContext context, SmartViewController c) {
    return SvInsightSheet.show(
      context,
      title: 'KPIs',
      icon: Icons.insights_outlined,
      tone: AppTones.primary,
      body: SvKpiBody(controller: c),
    );
  }
}

class SvKpiBody extends StatelessWidget {
  const SvKpiBody({super.key, required this.controller});

  final SmartViewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final input = c.engineInput;
      if (input == null) return const SizedBox.shrink();
      final rows = c.insightRows;
      final loaded = input.rows.length;
      final hasMore = c.hasMorePages;
      final tiles = SvInsights.kpis(
        input.table,
        rows,
        loaded: loaded,
        statusKey: input.statusKey,
        numberKeys: input.measureKeys,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvInsightNote(shown: rows.length, loaded: loaded, hasMore: hasMore),
          const SizedBox(height: AppSpacing.sm),
          if (loaded == 0)
            const SvInsightEmpty(
              icon: Icons.insights_outlined,
              title: 'No records yet',
              caption: 'Numbers show up when there are records',
            )
          else
            SvKpiGrid(
              key: ValueKey('kpi-${Object.hashAll(tiles.map((t) => t.id))}'),
              tiles: tiles,
            ),
        ],
      );
    });
  }
}

/// Tiles that come in one after another; a numeric value counts up.
class SvKpiGrid extends StatefulWidget {
  const SvKpiGrid({super.key, required this.tiles});

  final List<SvKpiTile> tiles;

  @override
  State<SvKpiGrid> createState() => _SvKpiGridState();
}

class _SvKpiGridState extends State<SvKpiGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  Duration get _total =>
      AppSv.kpiCount + AppSv.kpiStagger * (widget.tiles.length - 1);

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: _total);
  }

  bool _isStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isStarted) return;
    _isStarted = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _anim.value = 1;
    } else {
      _anim.forward();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = widget.tiles;
    final total = _total.inMilliseconds;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          const gap = AppSpacing.sm;
          return SvUniformGrid(
            gap: gap,
            children: [
              for (var i = 0; i < tiles.length; i++)
                _Tile(
                  tile: tiles[i],
                  t:
                      ((_anim.value * total -
                                  i * AppSv.kpiStagger.inMilliseconds) /
                              AppSv.kpiCount.inMilliseconds)
                          .clamp(0.0, 1.0),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Two columns of tiles that all share one size: half the width, and the
/// natural height of the tallest tile (measured at that width, so text scale
/// is respected). An odd last tile keeps the size and sits on the left.
class SvUniformGrid extends MultiChildRenderObjectWidget {
  const SvUniformGrid({super.key, required this.gap, required super.children});

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSvUniformGrid(gap);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSvUniformGrid renderObject,
  ) {
    renderObject.gap = gap;
  }
}

class _GridParentData extends ContainerBoxParentData<RenderBox> {}

class RenderSvUniformGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GridParentData> {
  RenderSvUniformGrid(this._gap);

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GridParentData) {
      child.parentData = _GridParentData();
    }
  }

  List<RenderBox> get _kids {
    final out = <RenderBox>[];
    var c = firstChild;
    while (c != null) {
      out.add(c);
      c = (c.parentData! as _GridParentData).nextSibling;
    }
    return out;
  }

  double _tileWidth(double maxWidth) => (maxWidth - _gap) / 2;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final kids = _kids;
    if (kids.isEmpty) return constraints.smallest;
    final w = _tileWidth(constraints.maxWidth);
    final tight = BoxConstraints.tightFor(width: w);
    var h = 0.0;
    for (final k in kids) {
      h = math.max(h, k.getDryLayout(tight).height);
    }
    final rows = (kids.length + 1) ~/ 2;
    return constraints.constrain(
      Size(constraints.maxWidth, rows * h + (rows - 1) * _gap),
    );
  }

  @override
  void performLayout() {
    final kids = _kids;
    if (kids.isEmpty) {
      size = constraints.smallest;
      return;
    }
    final w = _tileWidth(constraints.maxWidth);
    var h = 0.0;
    for (final k in kids) {
      k.layout(BoxConstraints.tightFor(width: w), parentUsesSize: true);
      h = math.max(h, k.size.height);
    }
    for (var i = 0; i < kids.length; i++) {
      kids[i].layout(BoxConstraints.tightFor(width: w, height: h));
      (kids[i].parentData! as _GridParentData).offset = Offset(
        (i % 2) * (w + _gap),
        (i ~/ 2) * (h + _gap),
      );
    }
    final rows = (kids.length + 1) ~/ 2;
    size = constraints.constrain(
      Size(constraints.maxWidth, rows * h + (rows - 1) * _gap),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

AppTone _toneOf(String tone) => switch (tone) {
  'green' => AppTones.green,
  'waiting' => AppTones.violet,
  'red' => AppTones.red,
  _ => AppTones.primary,
};

IconData _iconOf(String icon) => switch (icon) {
  'functions' => Icons.functions,
  'avg_pace' => Icons.speed,
  'arrow_downward' => Icons.arrow_downward,
  'arrow_upward' => Icons.arrow_upward,
  'cancel' => Icons.cancel_outlined,
  'schedule' => Icons.schedule,
  'check_circle' => Icons.check_circle_outline,
  _ => Icons.tag,
};

class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.t});

  final SvKpiTile tile;
  final double t;

  @override
  Widget build(BuildContext context) {
    final tone = _toneOf(tile.tone);
    final eased = AppCurves.out.transform(t);
    final v = tile.value;
    final isCounting = v.isFinite && v.abs() <= 1e9;
    final shown = isCounting ? v * eased : v;
    final isWhole = v == v.roundToDouble();
    final text = SvInsights.format(
      isWhole && !isCounting
          ? v
          : isWhole
          ? shown.roundToDouble()
          : shown,
    );
    return Opacity(
      opacity: eased,
      child: Transform.translate(
        offset: Offset(0, (1 - eased) * AppDistances.tab),
        child: Container(
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppSv.cardRadius),
            border: Border.all(color: AppSv.cardBorder),
            boxShadow: AppSv.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: AppSv.kpiIconCircle,
                height: AppSv.kpiIconCircle,
                decoration: BoxDecoration(
                  color: tone.solid.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_iconOf(tile.icon), size: 16, color: tone.solid),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                tile.label,
                style: AppSv.kpiLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(text, style: AppSv.kpiValue, maxLines: 1),
              ),
              if (tile.sub.isNotEmpty)
                Text(
                  tile.sub,
                  style: AppSv.kpiSub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
