import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_refresh.dart';
import '../../../data/smart_view/models/sv_row.dart';
import '../../../data/smart_view/models/sv_source.dart';
import '../../../data/smart_view/sv_columns.dart';
import 'smart_view_status_pill.dart';
import 'sv_sort_sheet.dart';

/// Measured column widths and row heights of a table: every column is as
/// wide as its widest content (header and all loaded cells) up to
/// [maxWidth], and a longer value wraps onto more lines instead of being
/// cut. Pure: the same input gives the same numbers.
class SmartViewTableMetrics {
  SmartViewTableMetrics._(this.widths, this.rowHeights, this.headerHeight);

  static const minWidth = 64.0;
  static const padX = AppSpacing.md;
  static const padY = AppSpacing.sm;
  static const minRowHeight = 48.0;
  static const minHeaderHeight = 44.0;
  static const _pillExtra = 6 + 6 + AppSpacing.xs + AppSpacing.sm;

  final List<double> widths;
  final List<double> rowHeights;
  final double headerHeight;

  double get total => widths.fold(0, (a, b) => a + b);

  static TextStyle cellStyle = AppText.readable.copyWith(color: AppColors.ink);
  static TextStyle headerStyle = AppText.readableStrong.copyWith(
    color: AppColors.muted,
  );

  static SmartViewTableMetrics measure({
    required SmartViewColumns columns,
    required List<SvRow> rows,
    required double maxWidth,
    TextScaler textScaler = TextScaler.noScaling,
    TextStyle base = const TextStyle(),
  }) {
    final cols = columns.columns;
    final cells = [for (final r in rows) columns.cellsOf(r)];
    final painter = TextPainter(textDirection: TextDirection.ltr);

    Size size(String text, TextStyle style, double width) {
      painter
        ..text = TextSpan(text: text, style: base.merge(style))
        ..textScaler = textScaler
        ..layout(maxWidth: width);
      return painter.size;
    }

    bool isPill(SvColumn c, SvCellValue v) =>
        c.type == SvColType.status && !v.isEmpty;
    TextStyle styleOf(SvColumn c, SvCellValue v) =>
        isPill(c, v) ? AppText.readableStrong : cellStyle;
    double extraOf(SvColumn c, SvCellValue v) => isPill(c, v) ? _pillExtra : 0;

    final widths = <double>[];
    for (var i = 0; i < cols.length; i++) {
      var w = size(cols[i].label, headerStyle, double.infinity).width;
      for (final row in cells) {
        final v = row[i];
        final cw =
            size(v.text, styleOf(cols[i], v), double.infinity).width +
            extraOf(cols[i], v);
        if (cw > w) w = cw;
      }
      // A pill is one line and is never cut, so it is not capped.
      final cap = cols[i].type == SvColType.status ? double.infinity : maxWidth;
      widths.add((w + 2 * padX).ceilToDouble().clamp(minWidth, cap));
    }

    double heightOf(String text, TextStyle style, double colWidth) =>
        size(text, style, colWidth - 2 * padX).height + 2 * padY;

    var header = minHeaderHeight;
    for (var i = 0; i < cols.length; i++) {
      final h = heightOf(cols[i].label, headerStyle, widths[i]);
      if (h > header) header = h;
    }
    final heights = <double>[];
    for (final row in cells) {
      var h = minRowHeight;
      for (var i = 0; i < cols.length; i++) {
        final v = row[i];
        if (isPill(cols[i], v)) continue;
        final ch = heightOf(v.text, cellStyle, widths[i]);
        if (ch > h) h = ch;
      }
      heights.add(h.ceilToDouble());
    }
    return SmartViewTableMetrics._(widths, heights, header.ceilToDouble());
  }
}

/// Remembers the last measurement of one table, by what it was measured for.
class SmartViewTableCache {
  Object? _key;
  SmartViewTableMetrics? _metrics;

  SmartViewTableMetrics of(Object key, SmartViewTableMetrics Function() build) {
    if (_metrics == null || _key != key) {
      _key = key;
      _metrics = build();
    }
    return _metrics!;
  }
}

/// The records as a table: a sticky header, hairline row lines, every cell
/// as wide as its content, the page scrolling sideways when it is wider than
/// the screen. Reads [SmartViewColumns], the same source as the cards.
class SmartViewTable extends StatefulWidget {
  const SmartViewTable({
    super.key,
    required this.source,
    required this.rows,
    required this.versions,
    required this.onRefresh,
    required this.footer,
    this.onRowTap,
    this.cache,
    this.sortKey,
    this.isAscending = true,
    this.onSort,
  });

  final SvSource source;
  final List<SvRow> rows;
  final Map<int, int> versions;
  final Future<void> Function() onRefresh;
  final Widget footer;
  final void Function(SvRow row)? onRowTap;
  final SmartViewTableCache? cache;

  /// The column the rows are sorted by (null: as they come) and the
  /// direction; a header tap calls [onSort] with the column's key.
  final String? sortKey;
  final bool isAscending;
  final void Function(String key)? onSort;

  @override
  State<SmartViewTable> createState() => _SmartViewTableState();
}

class _SmartViewTableState extends State<SmartViewTable> {
  final _h = ScrollController();
  late final _ownCache = SmartViewTableCache();

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final viewport = box.maxWidth;
        final columns = SmartViewColumns.of(widget.source);
        final rows = widget.rows;
        final key = Object.hash(
          widget.source.name,
          rows.length,
          Object.hashAll(rows.map((r) => r.id)),
          widget.versions.values.fold<int>(0, (a, b) => a + b),
          viewport,
          scaler.scale(10),
          DefaultTextStyle.of(context).style,
        );
        final m = (widget.cache ?? _ownCache).of(
          key,
          () => SmartViewTableMetrics.measure(
            columns: columns,
            rows: rows,
            maxWidth: viewport * 0.6,
            textScaler: scaler,
            base: DefaultTextStyle.of(context).style,
          ),
        );
        final width = m.total < viewport ? viewport : m.total;
        return SingleChildScrollView(
          controller: _h,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            width: width,
            height: box.maxHeight,
            child: Column(
              children: [
                _HeaderRow(
                  columns: columns,
                  metrics: m,
                  sortKey: widget.sortKey,
                  isAscending: widget.isAscending,
                  onSort: widget.onSort,
                ),
                Expanded(
                  child: AppRefresh(
                    onRefresh: widget.onRefresh,
                    wrapSpinner: (spinner) => AnimatedBuilder(
                      animation: _h,
                      builder: (context, child) => Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left:
                                (_h.hasClients ? _h.offset : 0) +
                                (viewport - AppSpacing.spinnerPull) / 2,
                          ),
                          child: child,
                        ),
                      ),
                      child: spinner,
                    ),
                    slivers: [
                      SliverList.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) => _DataRow(
                          key: ValueKey('svt-${rows[i].id}'),
                          columns: columns,
                          row: rows[i],
                          metrics: m,
                          height: m.rowHeights[i],
                          onTap: widget.onRowTap,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: viewport,
                            child: widget.footer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.columns,
    required this.metrics,
    required this.sortKey,
    required this.isAscending,
    required this.onSort,
  });

  final SmartViewColumns columns;
  final SmartViewTableMetrics metrics;
  final String? sortKey;
  final bool isAscending;
  final void Function(String key)? onSort;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: metrics.headerHeight,
      decoration: const BoxDecoration(
        color: AppColors.surfaceSubtle,
        border: Border(
          top: BorderSide(color: AppColors.line),
          bottom: BorderSide(color: AppColors.line),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < columns.columns.length; i++)
            _HeaderCell(
              column: columns.columns[i],
              width: metrics.widths[i],
              sortState: sortKey == columns.columns[i].key ? isAscending : null,
              onSort: onSort,
            ),
        ],
      ),
    );
  }
}

/// One header cell. A tap asks for the next sort of its column; the arrow
/// sits in the cell's right padding, so the header measures as before.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.width,
    required this.sortState,
    required this.onSort,
  });

  final SvColumn column;
  final double width;

  /// Null: not sorted by this column; true ascending; false descending.
  final bool? sortState;
  final void Function(String key)? onSort;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onSort != null,
      label: 'Sort by ${column.label}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSort == null ? null : () => onSort!(column.key),
        child: Container(
          width: width,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(
            horizontal: SmartViewTableMetrics.padX,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Text(column.label, style: SmartViewTableMetrics.headerStyle),
              Positioned(
                right: -SmartViewTableMetrics.padX + AppSpacing.xxs / 2,
                child: AnimatedOpacity(
                  opacity: sortState == null ? 0 : 1,
                  duration: AppDurations.smartChip,
                  child: SvSortArrow(
                    isAscending: sortState ?? true,
                    color: AppColors.violetStrong,
                    size: AppSpacing.pillChevron - 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    super.key,
    required this.columns,
    required this.row,
    required this.metrics,
    required this.height,
    required this.onTap,
  });

  final SmartViewColumns columns;
  final SvRow row;
  final SmartViewTableMetrics metrics;
  final double height;
  final void Function(SvRow row)? onTap;

  @override
  Widget build(BuildContext context) {
    final cells = columns.cellsOf(row);
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null ? null : () => onTap!(row),
        child: Container(
          height: height,
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++)
                Container(
                  width: metrics.widths[i],
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: SmartViewTableMetrics.padX,
                  ),
                  child:
                      columns.columns[i].type == SvColType.status &&
                          !cells[i].isEmpty
                      ? SmartViewStatusPill(label: cells[i].text)
                      : Text(
                          cells[i].text,
                          style: cells[i].isEmpty
                              ? SmartViewTableMetrics.cellStyle.copyWith(
                                  color: AppColors.cardMuted,
                                )
                              : SmartViewTableMetrics.cellStyle,
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
