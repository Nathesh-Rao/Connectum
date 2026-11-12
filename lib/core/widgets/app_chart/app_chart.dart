import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_chart_colors.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text.dart';
import 'app_chart_data.dart';

/// A chart drawn with `CustomPainter` (no chart package): bars (horizontal),
/// columns, lines and a donut, single or multi series. It grows in once, not
/// again on rebuilds, and not at all when the system asks for no animation.
/// Tapping a bar, point or segment shows its label and value.
class AppChart extends StatefulWidget {
  const AppChart(this.data, {super.key});

  final AppChartData data;

  @override
  State<AppChart> createState() => _AppChartState();
}

class _Hit {
  const _Hit(this.anchor, this.text);

  final Offset anchor;
  final String text;
}

class _AppChartState extends State<AppChart>
    with SingleTickerProviderStateMixin {
  static const double _plotHeight = 200;
  static const double _donutHeight = 200;
  static const double _barRow = 28;
  static const int _maxBars = 12;
  static const double _minBar = 12;
  static const double _barGap = 3;

  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: AppDurations.chartGrow,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _grow,
    curve: AppCurves.out,
  );
  final _hit = ValueNotifier<_Hit?>(null);
  bool _hasStarted = false;

  AppChartData get _d => widget.data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasStarted) return;
    _hasStarted = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _grow.value = 1;
    } else {
      _grow.forward();
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    _hit.dispose();
    super.dispose();
  }

  Color _color(int i) =>
      AppChartColors.series[i % AppChartColors.series.length];

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Semantics(
      container: true,
      label: d.describe(),
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d.title.isNotEmpty || d.unit.isNotEmpty) _header(d),
            LayoutBuilder(
              builder: (context, box) => switch (d.type) {
                AppChartType.donut => _donut(box.maxWidth),
                AppChartType.bar => _bars(box.maxWidth),
                _ => _columns(box.maxWidth),
              },
            ),
            if (d.isMulti)
              _legend([
                for (var i = 0; i < d.series.length; i++)
                  (
                    _color(i),
                    d.series[i].name.isEmpty
                        ? 'Series ${i + 1}'
                        : d.series[i].name,
                    null,
                  ),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _header(AppChartData d) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text.rich(
      TextSpan(
        children: [
          if (d.title.isNotEmpty)
            TextSpan(text: d.title, style: AppText.bodyStrong),
          if (d.title.isNotEmpty && d.unit.isNotEmpty)
            const TextSpan(text: '  '),
          if (d.unit.isNotEmpty)
            TextSpan(
              text: d.unit,
              style: AppText.readable.copyWith(color: AppColors.muted),
            ),
        ],
      ),
    ),
  );

  Widget _legend(List<(Color, String, String?)> items) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: [
        for (final (color, name, value) in items)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: AppColors.ink),
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: AppColors.muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    ),
  );

  // ---- columns and lines ----

  double _textHeight(BuildContext context) {
    final p = _tp('Ag', _labelStyle, 1000, MediaQuery.textScalerOf(context));
    return p.height;
  }

  Widget _columns(double width) {
    final d = _d;
    final scaler = MediaQuery.textScalerOf(context);
    final values = _allValues();
    final ticks = AppChartData.niceTicks(values.min, values.max);
    final lineH = _textHeight(context);
    final top = lineH + 6;
    final bottom = lineH + 10;
    var yW = 0.0;
    for (final t in ticks) {
      yW = math.max(
        yW,
        _tp(AppChartData.format(t), _labelStyle, 120, scaler).width,
      );
    }
    yW += 6;
    final s = d.series.length;
    final isColumn = d.type == AppChartType.column;
    final minSlot = math.max(
      44.0,
      isColumn ? s * (_minBar + _barGap) + 12.0 : 0.0,
    );
    final avail = math.max(0.0, width - yW);
    final n = d.labels.length;
    final slot = n <= 8 ? avail / n : math.max(avail / n, minSlot);
    final contentW = math.max(avail, slot * n);
    final painter = _ColumnPainter(
      data: d,
      ticks: ticks,
      scaler: scaler,
      progress: _t,
      slot: slot,
      top: top,
      bottom: bottom,
      isColumn: isColumn,
      colorOf: _color,
      repaint: _t,
    );
    return SizedBox(
      height: _plotHeight,
      child: Row(
        children: [
          SizedBox(
            width: yW,
            child: CustomPaint(
              size: Size(yW, _plotHeight),
              painter: _YAxisPainter(ticks, top, bottom, scaler),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: contentW > avail
                  ? null
                  : const NeverScrollableScrollPhysics(),
              child: _canvas(Size(contentW, _plotHeight), painter, painter.hit),
            ),
          ),
        ],
      ),
    );
  }

  ({double min, double max}) _allValues() {
    var lo = 0.0, hi = 0.0;
    for (final s in _d.series) {
      for (final v in s.values) {
        if (v == null) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    return (min: lo, max: hi);
  }

  Widget _canvas(Size size, CustomPainter painter, _Hit? Function(Offset) hit) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final h = hit(details.localPosition);
          _hit.value = (h == null || _hit.value?.text == h.text) ? null : h;
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: CustomPaint(painter: painter)),
            Positioned.fill(child: _tooltip()),
          ],
        ),
      ),
    );
  }

  Widget _tooltip() => IgnorePointer(
    child: ValueListenableBuilder<_Hit?>(
      valueListenable: _hit,
      builder: (context, hit, _) {
        if (hit == null) return const SizedBox.shrink();
        return CustomSingleChildLayout(
          delegate: _TooltipLayout(hit.anchor),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(
              hit.text,
              style: AppText.caption.copyWith(color: AppColors.white),
            ),
          ),
        );
      },
    ),
  );

  // ---- horizontal bars ----

  Widget _bars(double width) {
    final d = _d;
    final scaler = MediaQuery.textScalerOf(context);
    final shown = math.min(d.labels.length, _maxBars);
    final more = d.labels.length - shown;
    final s = d.series.length;
    final rowH = s == 1 ? _barRow : s * 14.0 + 10;
    final values = _allValues();
    final ticks = AppChartData.niceTicks(values.min, values.max, target: 3);
    final lineH = _textHeight(context);
    var labelW = 0.0;
    for (var i = 0; i < shown; i++) {
      labelW = math.max(
        labelW,
        _tp(d.labels[i], _labelStyle, 1000, scaler).width,
      );
    }
    labelW = labelW.clamp(48.0, math.max(48.0, width * 0.36));
    var valueW = 0.0;
    for (final sr in d.series) {
      for (var i = 0; i < shown; i++) {
        final v = sr.values[i];
        if (v != null) {
          valueW = math.max(
            valueW,
            _tp(AppChartData.format(v), _labelStyle, 200, scaler).width,
          );
        }
      }
    }
    valueW = math.min(valueW + 6, width * 0.25);
    final axisH = lineH + 8;
    final height = shown * rowH + axisH;
    final painter = _BarPainter(
      data: d,
      shown: shown,
      ticks: ticks,
      scaler: scaler,
      progress: _t,
      rowH: rowH,
      labelW: labelW,
      valueW: valueW,
      axisH: axisH,
      colorOf: _color,
      repaint: _t,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _canvas(Size(width, height), painter, painter.hit),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              '+$more more',
              style: AppText.caption.copyWith(color: AppColors.muted),
            ),
          ),
      ],
    );
  }

  // ---- donut ----

  Widget _donut(double width) {
    final d = _d;
    final s = d.series.first;
    final parts = <(int, String, double)>[
      for (var i = 0; i < d.labels.length; i++)
        if (s.values[i] != null && s.values[i]! > 0)
          (i, d.labels[i], s.values[i]!),
    ];
    final total = parts.fold<double>(0, (a, p) => a + p.$3);
    final unit = d.unit.isEmpty ? '' : ' ${d.unit}';
    final painter = _DonutPainter(
      parts: parts,
      total: total,
      progress: _t,
      colorOf: _color,
      repaint: Listenable.merge([_t, _hit]),
      selected: _hit,
      format: (v) => '${AppChartData.format(v)}$unit',
    );
    final ring = Size(math.min(width, _donutHeight), _donutHeight);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SizedBox(
            width: ring.width,
            height: ring.height,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _canvas(ring, painter, painter.hit),
                if (total > 0)
                  IgnorePointer(
                    child: SizedBox(
                      width: ring.width * 0.5,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${AppChartData.format(total)}$unit',
                              style: AppText.bodyStrong,
                            ),
                            Text(
                              'Total',
                              style: AppText.caption.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        _legend([
          for (final (i, label, v) in parts)
            (
              _color(i),
              label,
              '${AppChartData.format(v)}$unit · ${_percent(v / total * 100)}',
            ),
        ]),
      ],
    );
  }
}

String _percent(double p) => p == p.roundToDouble() || p >= 10
    ? '${p.round()}%'
    : '${p.toStringAsFixed(1)}%';

const _labelStyle = TextStyle(
  fontFamily: AppText.fontFamily,
  fontSize: AppText.sizeCaption,
  height: 1.2,
  color: AppColors.muted,
);

TextPainter _tp(
  String text,
  TextStyle style,
  double maxWidth,
  TextScaler scaler, {
  TextAlign align = TextAlign.start,
}) {
  return TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    textAlign: align,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: math.max(1, maxWidth));
}

double _yOf(
  double v,
  List<double> ticks,
  double top,
  double bottom,
  double height,
) {
  final lo = ticks.first, hi = ticks.last;
  final span = hi - lo == 0 ? 1 : hi - lo;
  return height - bottom - (v - lo) / span * (height - top - bottom);
}

class _YAxisPainter extends CustomPainter {
  _YAxisPainter(this.ticks, this.top, this.bottom, this.scaler);

  final List<double> ticks;
  final double top;
  final double bottom;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in ticks) {
      final p = _tp(AppChartData.format(t), _labelStyle, size.width, scaler);
      final y = _yOf(t, ticks, top, bottom, size.height);
      p.paint(canvas, Offset(size.width - p.width - 6, y - p.height / 2));
    }
  }

  @override
  bool shouldRepaint(_YAxisPainter old) =>
      old.ticks != ticks || old.scaler != scaler;
}

class _TooltipLayout extends SingleChildLayoutDelegate {
  const _TooltipLayout(this.anchor);

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.dx - childSize.width / 2;
    var y = anchor.dy - childSize.height - 6;
    x = x.clamp(0.0, math.max(0.0, size.width - childSize.width));
    if (y < 0) {
      y = math.min(
        anchor.dy + 8,
        math.max(0.0, size.height - childSize.height),
      );
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_TooltipLayout old) => old.anchor != anchor;
}

String _tipText(AppChartData d, int s, int i) {
  final v = d.series[s].values[i]!;
  final unit = d.unit.isEmpty ? '' : ' ${d.unit}';
  final name = d.isMulti && d.series[s].name.isNotEmpty
      ? '${d.series[s].name} · '
      : '';
  return '$name${d.labels[i]}: ${AppChartData.format(v)}$unit';
}

class _ColumnPainter extends CustomPainter {
  _ColumnPainter({
    required this.data,
    required this.ticks,
    required this.scaler,
    required this.progress,
    required this.slot,
    required this.top,
    required this.bottom,
    required this.isColumn,
    required this.colorOf,
    super.repaint,
  });

  final AppChartData data;
  final List<double> ticks;
  final TextScaler scaler;
  final Animation<double> progress;
  final double slot;
  final double top;
  final double bottom;
  final bool isColumn;
  final Color Function(int) colorOf;

  static const _gap = 3.0;

  double get _barW {
    final s = data.series.length;
    final group = slot - math.max(6.0, slot * 0.18) * 2;
    return ((group - (s - 1) * _gap) / s).clamp(12.0, 28.0);
  }

  double _barLeft(int s, int i) {
    final n = data.series.length;
    final total = n * _barW + (n - 1) * _gap;
    return i * slot + slot / 2 - total / 2 + s * (_barW + _gap);
  }

  double _height = 0;

  _Hit? hit(Offset p) {
    final h = _height;
    for (var s = 0; s < data.series.length; s++) {
      for (var i = 0; i < data.labels.length; i++) {
        final v = data.series[s].values[i];
        if (v == null) continue;
        final y = _yOf(v, ticks, top, bottom, h);
        if (isColumn) {
          final l = _barLeft(s, i);
          final y0 = _yOf(0, ticks, top, bottom, h);
          final r = Rect.fromLTRB(
            l - 3,
            math.min(y, y0) - 4,
            l + _barW + 3,
            math.max(y, y0) + 4,
          );
          if (r.contains(p)) {
            return _Hit(
              Offset(l + _barW / 2, math.min(y, y0)),
              _tipText(data, s, i),
            );
          }
        } else {
          final c = Offset(i * slot + slot / 2, y);
          if ((c - p).distance <= 18) return _Hit(c, _tipText(data, s, i));
        }
      }
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _height = size.height;
    final t = progress.value;
    final grid = Paint()
      ..color = AppChartColors.grid
      ..strokeWidth = 1;
    for (final tick in ticks) {
      final y = _yOf(tick, ticks, top, bottom, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final y0 = _yOf(0, ticks, top, bottom, size.height);
    canvas.drawLine(
      Offset(0, y0),
      Offset(size.width, y0),
      Paint()
        ..color = AppChartColors.baseline
        ..strokeWidth = 1.2,
    );
    for (var i = 0; i < data.labels.length; i++) {
      final p = _tp(
        data.labels[i],
        _labelStyle,
        slot - 4,
        scaler,
        align: TextAlign.center,
      );
      p.paint(
        canvas,
        Offset(i * slot + (slot - p.width) / 2, size.height - bottom + 6),
      );
    }
    if (isColumn) {
      _columns(canvas, size, t, y0);
    } else {
      _lines(canvas, size, t, y0);
    }
  }

  void _columns(Canvas canvas, Size size, double t, double y0) {
    for (var s = 0; s < data.series.length; s++) {
      final paint = Paint()..color = colorOf(s);
      for (var i = 0; i < data.labels.length; i++) {
        final v = data.series[s].values[i];
        if (v == null) continue;
        final y = y0 + (_yOf(v, ticks, top, bottom, size.height) - y0) * t;
        final l = _barLeft(s, i);
        final isUp = y <= y0;
        final rect = Rect.fromLTRB(
          l,
          math.min(y, y0),
          l + _barW,
          math.max(y, y0),
        );
        const r = Radius.circular(4);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: isUp ? r : Radius.zero,
            topRight: isUp ? r : Radius.zero,
            bottomLeft: isUp ? Radius.zero : r,
            bottomRight: isUp ? Radius.zero : r,
          ),
          paint,
        );
        if (t < 1) continue;
        final label = _tp(AppChartData.format(v), _labelStyle, 200, scaler);
        final room = data.series.length == 1 ? slot - 2 : _barW + _gap * 2;
        if (label.width <= room) {
          label.paint(
            canvas,
            Offset(
              l + _barW / 2 - label.width / 2,
              isUp ? rect.top - label.height - 2 : rect.bottom + 2,
            ),
          );
        }
      }
    }
  }

  void _lines(Canvas canvas, Size size, double t, double y0) {
    for (var s = 0; s < data.series.length; s++) {
      final color = colorOf(s);
      final path = Path();
      var isOpen = false;
      final points = <Offset>[];
      for (var i = 0; i < data.labels.length; i++) {
        final v = data.series[s].values[i];
        if (v == null) {
          isOpen = false;
          continue;
        }
        final y = y0 + (_yOf(v, ticks, top, bottom, size.height) - y0) * t;
        final c = Offset(i * slot + slot / 2, y);
        points.add(c);
        if (isOpen) {
          path.lineTo(c.dx, c.dy);
        } else {
          path.moveTo(c.dx, c.dy);
          isOpen = true;
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      for (final c in points) {
        canvas.drawCircle(c, 4.2, Paint()..color = AppColors.white);
        canvas.drawCircle(c, 3, Paint()..color = color);
      }
    }
    if (t < 1 || data.series.length > 1 || data.labels.length > 8) return;
    for (var i = 0; i < data.labels.length; i++) {
      final v = data.series.first.values[i];
      if (v == null) continue;
      final label = _tp(AppChartData.format(v), _labelStyle, 200, scaler);
      if (label.width > slot - 2) continue;
      final y = _yOf(v, ticks, top, bottom, size.height);
      label.paint(
        canvas,
        Offset(i * slot + slot / 2 - label.width / 2, y - label.height - 6),
      );
    }
  }

  @override
  bool shouldRepaint(_ColumnPainter old) =>
      old.data != data || old.slot != slot || old.scaler != scaler;
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.data,
    required this.shown,
    required this.ticks,
    required this.scaler,
    required this.progress,
    required this.rowH,
    required this.labelW,
    required this.valueW,
    required this.axisH,
    required this.colorOf,
    super.repaint,
  });

  final AppChartData data;
  final int shown;
  final List<double> ticks;
  final TextScaler scaler;
  final Animation<double> progress;
  final double rowH;
  final double labelW;
  final double valueW;
  final double axisH;
  final Color Function(int) colorOf;

  double _width = 0;

  double _xOf(double v) {
    final left = labelW + 8, right = _width - valueW;
    final lo = ticks.first, hi = ticks.last;
    final span = hi - lo == 0 ? 1 : hi - lo;
    return left + (v - lo) / span * (right - left);
  }

  Rect _bar(int s, int i, double v, double t) {
    final n = data.series.length;
    final bh = n == 1 ? 14.0 : 12.0;
    final total = n * bh + (n - 1) * 2;
    final y = i * rowH + rowH / 2 - total / 2 + s * (bh + 2);
    final x0 = _xOf(0);
    final x = x0 + (_xOf(v) - x0) * t;
    return Rect.fromLTRB(math.min(x, x0), y, math.max(x, x0), y + bh);
  }

  _Hit? hit(Offset p) {
    for (var s = 0; s < data.series.length; s++) {
      for (var i = 0; i < shown; i++) {
        final v = data.series[s].values[i];
        if (v == null) continue;
        final r = _bar(s, i, v, 1).inflate(4);
        final row = Rect.fromLTWH(0, i * rowH, _width, rowH);
        if (r.contains(p) || (data.series.length == 1 && row.contains(p))) {
          final b = _bar(s, i, v, 1);
          return _Hit(Offset(b.right, b.top), _tipText(data, s, i));
        }
      }
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _width = size.width;
    final t = progress.value;
    final plotBottom = shown * rowH;
    final grid = Paint()
      ..color = AppChartColors.grid
      ..strokeWidth = 1;
    for (final tick in ticks) {
      final x = _xOf(tick);
      canvas.drawLine(Offset(x, 0), Offset(x, plotBottom), grid);
      final p = _tp(AppChartData.format(tick), _labelStyle, 80, scaler);
      p.paint(canvas, Offset(x - p.width / 2, plotBottom + 4));
    }
    final x0 = _xOf(0);
    canvas.drawLine(
      Offset(x0, 0),
      Offset(x0, plotBottom),
      Paint()
        ..color = AppChartColors.baseline
        ..strokeWidth = 1.2,
    );
    for (var i = 0; i < shown; i++) {
      final label = _tp(data.labels[i], _labelStyle, labelW, scaler);
      label.paint(canvas, Offset(0, i * rowH + (rowH - label.height) / 2));
    }
    for (var s = 0; s < data.series.length; s++) {
      final paint = Paint()..color = colorOf(s);
      for (var i = 0; i < shown; i++) {
        final v = data.series[s].values[i];
        if (v == null) continue;
        final r = _bar(s, i, v, t);
        final isRight = v >= 0;
        const c = Radius.circular(4);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            r,
            topRight: isRight ? c : Radius.zero,
            bottomRight: isRight ? c : Radius.zero,
            topLeft: isRight ? Radius.zero : c,
            bottomLeft: isRight ? Radius.zero : c,
          ),
          paint,
        );
        if (t < 1) continue;
        final label = _tp(AppChartData.format(v), _labelStyle, valueW, scaler);
        final fitsRight = isRight && r.right + 4 + label.width <= size.width;
        if (fitsRight) {
          label.paint(
            canvas,
            Offset(r.right + 4, r.center.dy - label.height / 2),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.data != data || old.labelW != labelW || old.scaler != scaler;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.parts,
    required this.total,
    required this.progress,
    required this.colorOf,
    required this.format,
    required this.selected,
    super.repaint,
  });

  final List<(int, String, double)> parts;
  final double total;
  final Animation<double> progress;
  final Color Function(int) colorOf;
  final String Function(double) format;
  final ValueNotifier<_Hit?> selected;

  static const _stroke = 14.0;

  Size _size = Size.zero;

  double get _radius =>
      math.min(_size.width, _size.height) / 2 - _stroke / 2 - 4;

  _Hit? hit(Offset p) {
    if (total <= 0) return null;
    final c = Offset(_size.width / 2, _size.height / 2);
    final d = p - c;
    final dist = d.distance;
    if (dist < _radius - _stroke || dist > _radius + _stroke) return null;
    var a = math.atan2(d.dy, d.dx) + math.pi / 2;
    if (a < 0) a += 2 * math.pi;
    var from = 0.0;
    for (final part in parts) {
      final sweep = part.$3 / total * 2 * math.pi;
      if (a >= from && a < from + sweep) {
        final mid = from + sweep / 2 - math.pi / 2;
        final anchor =
            c + Offset(math.cos(mid), math.sin(mid)) * (_radius - _stroke / 2);
        return _Hit(anchor, '${part.$2}: ${format(part.$3)}');
      }
      from += sweep;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: _radius);
    if (total <= 0) {
      canvas.drawCircle(
        c,
        _radius,
        Paint()
          ..color = AppChartColors.grid
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke,
      );
      return;
    }
    final t = progress.value;
    final gap = parts.length > 1 ? 0.03 : 0.0;
    var start = -math.pi / 2;
    for (final part in parts) {
      final full = part.$3 / total * 2 * math.pi;
      final sweep = math.max(0.0, full * t - gap);
      final isSelected =
          selected.value?.text == '${part.$2}: ${format(part.$3)}';
      canvas.drawArc(
        rect,
        start + gap / 2,
        sweep,
        false,
        Paint()
          ..color = colorOf(part.$1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? _stroke + 4 : _stroke,
      );
      start += full * t;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}
