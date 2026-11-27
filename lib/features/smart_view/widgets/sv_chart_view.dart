import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import '../../../data/smart_view/engine/sv_insights.dart';

Color svChartColor(SvChartPoint p) => p.colorIndex < 0
    ? AppSv.chartOthers
    : AppSv.chartPalette[p.colorIndex % AppSv.chartPalette.length];

/// A chart drawn with a [CustomPainter]. It draws itself in over
/// [AppSv.chartDraw] when it first shows and again whenever [data] or [kind]
/// changes.
class SvChartView extends StatefulWidget {
  const SvChartView({super.key, required this.data, required this.kind});

  final SvChartData data;
  final SvChartKind kind;

  static const barHeight = 200.0;
  static const barSlot = 56.0;
  static const donutSize = 190.0;

  @override
  State<SvChartView> createState() => _SvChartViewState();
}

class _SvChartViewState extends State<SvChartView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: AppSv.chartDraw,
  );

  bool _isStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isStarted) return;
    _isStarted = true;
    _play();
  }

  @override
  void didUpdateWidget(SvChartView old) {
    super.didUpdateWidget(old);
    if (!identical(old.data, widget.data) || old.kind != widget.kind) _play();
  }

  void _play() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _anim.value = 1;
    } else {
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final t = AppCurves.out.transform(_anim.value);
        return switch (widget.kind) {
          SvChartKind.bar => _Bars(data: d, t: t),
          SvChartKind.donut => _Donut(data: d, t: t),
          SvChartKind.line => _Line(data: d, t: t),
        };
      },
    );
  }
}

TextPainter _text(
  String s,
  TextStyle style,
  double maxWidth, {
  TextAlign align = TextAlign.center,
}) => TextPainter(
  text: TextSpan(text: s, style: style),
  textDirection: TextDirection.ltr,
  textAlign: align,
  maxLines: 1,
  ellipsis: '…',
)..layout(maxWidth: maxWidth);

class _Bars extends StatelessWidget {
  const _Bars({required this.data, required this.t});

  final SvChartData data;
  final double t;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = math.max(
          box.maxWidth,
          data.points.length * SvChartView.barSlot,
        );
        final chart = CustomPaint(
          size: Size(width, SvChartView.barHeight),
          painter: _BarPainter(data, t),
        );
        if (width <= box.maxWidth) return chart;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: chart,
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.data, this.t);

  final SvChartData data;
  final double t;

  static const _top = 22.0;
  static const _bottom = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = data.points;
    if (pts.isEmpty) return;
    final plotH = size.height - _top - _bottom;
    final base = size.height - _bottom;
    final grid = Paint()
      ..color = AppSv.chartGrid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = base - plotH * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final max = data.maxValue <= 0 ? 1.0 : data.maxValue;
    final slot = size.width / pts.length;
    final barW = math.min(30.0, slot * 0.58);
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      final cx = slot * (i + 0.5);
      final h = plotH * (p.value / max) * t;
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - barW / 2, base - h, barW, h),
        topLeft: const Radius.circular(7),
        topRight: const Radius.circular(7),
      );
      if (h > 0) canvas.drawRRect(r, Paint()..color = svChartColor(p));
      final value = _text(
        SvInsights.format(p.value, maxDecimals: 1),
        AppSv.chartValue.copyWith(color: AppColors.ink.withValues(alpha: t)),
        slot,
      );
      value.paint(canvas, Offset(cx - value.width / 2, base - h - 16));
      final label = _text(p.label, AppSv.chartLabel, slot - 4);
      label.paint(canvas, Offset(cx - label.width / 2, base + 8));
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.data != data || old.t != t;
}

class _Donut extends StatelessWidget {
  const _Donut({required this.data, required this.t});

  final SvChartData data;
  final double t;

  @override
  Widget build(BuildContext context) {
    final total = data.total;
    return Column(
      children: [
        Center(
          child: SizedBox(
            width: SvChartView.donutSize,
            height: SvChartView.donutSize,
            child: CustomPaint(
              painter: _DonutPainter(data, t),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      SvInsights.format(total, maxDecimals: 1),
                      style: AppSv.chartCenter,
                    ),
                    Text(
                      data.unit,
                      style: AppSv.chartLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final p in data.points) _LegendRow(point: p, total: total),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.point, required this.total});

  final SvChartPoint point;
  final double total;

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0 : (point.value * 100 / total).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: svChartColor(point),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              point.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(color: AppColors.ink),
            ),
          ),
          Text(
            SvInsights.format(point.value, maxDecimals: 1),
            style: AppText.bodyStrong,
          ),
          SizedBox(
            width: 52,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: AppText.body.copyWith(color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.data, this.t);

  final SvChartData data;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final total = data.total;
    const stroke = 28.0;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - stroke / 2,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppSv.chartGrid,
    );
    if (total <= 0) return;
    final gap = data.points.length > 1 ? 0.035 : 0.0;
    var start = -math.pi / 2;
    for (final p in data.points) {
      final full = math.pi * 2 * p.value / total;
      final sweep = math.max(0.0, full * t - gap);
      if (sweep > 0) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.butt
            ..color = svChartColor(p),
        );
      }
      start += full * t;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.data != data || old.t != t;
}

class _Line extends StatelessWidget {
  const _Line({required this.data, required this.t});

  final SvChartData data;
  final double t;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = math.max(
          box.maxWidth,
          data.points.length * SvChartView.barSlot * 0.8,
        );
        final chart = CustomPaint(
          size: Size(width, SvChartView.barHeight),
          painter: _LinePainter(data, t),
        );
        if (width <= box.maxWidth) return chart;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: chart,
        );
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.data, this.t);

  final SvChartData data;
  final double t;

  static const _top = 24.0;
  static const _bottom = 30.0;
  static const _side = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = data.points;
    if (pts.isEmpty) return;
    final plotH = size.height - _top - _bottom;
    final base = size.height - _bottom;
    final grid = Paint()
      ..color = AppSv.chartGrid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = base - plotH * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final max = data.maxValue <= 0 ? 1.0 : data.maxValue;
    final inner = size.width - 2 * _side;
    final xs = [
      for (var i = 0; i < pts.length; i++)
        pts.length == 1 ? size.width / 2 : _side + inner * i / (pts.length - 1),
    ];
    final ys = [for (final p in pts) base - plotH * p.value / max];
    final color = AppSv.chartPalette[0];

    final path = Path()..moveTo(xs.first, ys.first);
    for (var i = 0; i < pts.length - 1; i++) {
      final dx = (xs[i + 1] - xs[i]) / 2;
      path.cubicTo(
        xs[i] + dx,
        ys[i],
        xs[i + 1] - dx,
        ys[i + 1],
        xs[i + 1],
        ys[i + 1],
      );
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * t, size.height));
    final area = Path.from(path)
      ..lineTo(xs.last, base)
      ..lineTo(xs.first, base)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    for (var i = 0; i < pts.length; i++) {
      canvas.drawCircle(
        Offset(xs[i], ys[i]),
        5.5,
        Paint()..color = AppColors.white,
      );
      canvas.drawCircle(Offset(xs[i], ys[i]), 3.5, Paint()..color = color);
    }
    canvas.restore();
    final step = math.max(1, (pts.length / (size.width / 64)).ceil());
    for (var i = 0; i < pts.length; i += step) {
      final label = _text(pts[i].label, AppSv.chartLabel, 64);
      label.paint(canvas, Offset(xs[i] - label.width / 2, base + 8));
      final value = _text(
        SvInsights.format(pts[i].value, maxDecimals: 1),
        AppSv.chartValue.copyWith(color: AppColors.ink.withValues(alpha: t)),
        64,
      );
      value.paint(canvas, Offset(xs[i] - value.width / 2, ys[i] - 22));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.data != data || old.t != t;
}
