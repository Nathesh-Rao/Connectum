import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../../../data/smart_view/models/sv_row.dart';
import '../../../data/smart_view/models/sv_source.dart';
import '../../../data/smart_view/sv_columns.dart';
import '../smart_view_controller.dart' show SvGrouped;
import 'sv_group_header.dart';
import 'smart_view_status_pill.dart';
import 'sv_cell_details_sheet.dart';
import 'sv_file_chips.dart';
import 'sv_sort_sheet.dart';

/// Measured column widths of a table. Nothing wraps: every cell and header is
/// one line and every row has the same height. A text of more than
/// [AppSv.tableMaxWords] words, or one wider than the cap, is cut with "…"
/// and followed by a "View more" link; a column is as wide as its widest
/// cell after the cut (cap: 60 % of the screen). Pure: the same input gives
/// the same numbers.
class SmartViewTableMetrics {
  SmartViewTableMetrics._(
    this.widths,
    this.rowHeights,
    this.headerHeight,
    this.cut,
  );

  static const minWidth = 64.0;
  static const padX = AppSv.tableCellPadX;
  static const padY = AppSpacing.sm;
  static const minRowHeight = AppSv.tableRowMin;
  static const minHeaderHeight = 44.0;
  static const _pillExtra = 6 + 6 + AppSpacing.xs + AppSpacing.sm;
  static const ellipsis = '…';
  static const moreLabel = 'View more';

  final List<double> widths;
  final List<double> rowHeights;
  final double headerHeight;

  /// Per row, per column: the shortened text when the cell was cut (it then
  /// carries a "View more"), else null.
  final List<List<String?>> cut;

  double get total => widths.fold(0, (a, b) => a + b);

  static const cellStyle = AppSv.tableCell;
  static const headerStyle = AppSv.tableHead;

  static TextStyle cellStyleOf(SvColumn c) =>
      c.key == SmartViewColumns.noKey ? AppSv.tableCellNo : cellStyle;

  /// [text] cut to at most [AppSv.tableMaxWords] words and to [fits] (the
  /// widest text that still fits), or null when it needs no cut.
  static String? shorten(String text, bool Function(String) fits) {
    final words = text.trim().split(RegExp(r'\s+'));
    var out = text;
    var isCut = false;
    if (words.length > AppSv.tableMaxWords) {
      out = words.take(AppSv.tableMaxWords).join(' ');
      isCut = true;
    }
    if (!isCut && fits(out)) return null;
    if (!fits('$out$ellipsis')) {
      var lo = 0;
      var hi = out.length;
      while (lo < hi) {
        final mid = (lo + hi + 1) ~/ 2;
        if (fits('${out.substring(0, mid).trimRight()}$ellipsis')) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      out = out.substring(0, lo).trimRight();
    }
    return '$out$ellipsis';
  }

  static SmartViewTableMetrics measure({
    required SmartViewColumns columns,
    required List<SvRow> rows,
    required double maxWidth,
    TextScaler textScaler = TextScaler.noScaling,
    TextStyle base = const TextStyle(),
  }) {
    final cols = columns.columns;
    final cells = [for (final r in rows) columns.cellsOf(r)];
    final painter = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);

    Size size(String text, TextStyle style) {
      painter
        ..text = TextSpan(text: text, style: base.merge(style))
        ..textScaler = textScaler
        ..layout();
      return painter.size;
    }

    bool isPill(SvColumn c, SvCellValue v) =>
        c.type == SvColType.status && !v.isEmpty;
    TextStyle styleOf(SvColumn c, SvCellValue v) =>
        isPill(c, v) ? AppText.readableStrong : cellStyleOf(c);
    double extraOf(SvColumn c, SvCellValue v) => isPill(c, v) ? _pillExtra : 0;

    final moreWidth = size(moreLabel, AppSv.tableMore).width;
    final room = maxWidth - 2 * padX;
    final cuts = <List<String?>>[];
    final widths = <double>[];
    for (var r = 0; r < cells.length; r++) {
      cuts.add(List<String?>.filled(cols.length, null));
    }
    var lineHeight = 0.0;
    for (var i = 0; i < cols.length; i++) {
      final head = size(cols[i].label, headerStyle);
      var w = head.width;
      for (var r = 0; r < cells.length; r++) {
        final v = cells[r][i];
        final style = styleOf(cols[i], v);
        if (isPill(cols[i], v)) {
          final cw = size(v.text, style).width + extraOf(cols[i], v);
          if (cw > w) w = cw;
          continue;
        }
        if (cols[i].type == SvColType.file && v.files.isNotEmpty) {
          final cw =
              AppSv.fileChipMaxWidth +
              (v.files.length > 1 ? AppSv.fileChipGap + AppSv.fileMinHit : 0);
          if (cw > w) w = cw;
          continue;
        }
        final textRoom = room - moreWidth - AppSv.tableMoreGap;
        final short = v.isEmpty
            ? null
            : shorten(v.text, (t) => size(t, style).width <= room);
        double cw;
        if (short == null) {
          cw = size(v.text, style).width;
        } else {
          final fitted =
              shorten(short, (t) => size(t, style).width <= textRoom) ?? short;
          cuts[r][i] = fitted;
          cw = size(fitted, style).width + AppSv.tableMoreGap + moreWidth;
        }
        if (cw > w) w = cw;
        final h = size(v.text.isEmpty ? ' ' : v.text, style).height;
        if (h > lineHeight) lineHeight = h;
      }
      final cap = cols[i].type == SvColType.status ? double.infinity : maxWidth;
      widths.add((w + 2 * padX).ceilToDouble().clamp(minWidth, cap));
    }

    var header = minHeaderHeight;
    for (final c in cols) {
      final h = size(c.label, headerStyle).height + 2 * padY;
      if (h > header) header = h;
    }
    final rowHeight = (lineHeight + 2 * padY) > minRowHeight
        ? (lineHeight + 2 * padY).ceilToDouble()
        : minRowHeight;
    return SmartViewTableMetrics._(
      widths,
      List<double>.filled(cells.length, rowHeight),
      header.ceilToDouble(),
      cuts,
    );
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
    this.onOpenFiles,
    this.columns,
    this.grouped,
    this.onToggleGroup,
  });

  /// The columns as the view lays them out; null: every column.
  final SmartViewColumns? columns;

  /// Group headers between the rows (null: a plain list).
  final SvGrouped? grouped;
  final void Function(String path)? onToggleGroup;
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
  final SvFileOpener? onOpenFiles;

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
        final columns = widget.columns ?? SmartViewColumns.of(widget.source);
        final grouped = widget.grouped;
        final rows = grouped?.rows ?? widget.rows;
        final key = Object.hash(
          widget.source.name,
          rows.length,
          Object.hashAll(rows.map((r) => r.id)),
          Object.hashAll(columns.columns.map((c) => c.key)),
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
            maxWidth: viewport * AppSv.tableMaxWidthShare,
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
                const SizedBox(height: AppSv.tableTopGap),
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
                        itemCount: grouped?.flat.length ?? rows.length,
                        itemBuilder: (context, n) {
                          final line = grouped?.flat[n];
                          if (line != null && line.isGroup) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: width,
                                child: SvGroupHeader(
                                  line: line,
                                  sumLabel: grouped!.sumLabel,
                                  onTap: () =>
                                      widget.onToggleGroup?.call(line.path!),
                                ),
                              ),
                            );
                          }
                          final i = line?.row ?? n;
                          return _DataRow(
                            key: ValueKey('svt-${rows[i].id}'),
                            columns: columns,
                            row: rows[i],
                            cutCells: m.cut[i],
                            metrics: m,
                            height: m.rowHeights[i],
                            isBand: i.isOdd,
                            onTap: widget.onRowTap,
                            onOpenFiles: widget.onOpenFiles,
                          );
                        },
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
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height:
                              AppSv.dialClearance +
                              MediaQuery.paddingOf(context).bottom,
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
      color: AppSv.tableHeaderFill,
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
              Text(
                column.label,
                style: SmartViewTableMetrics.headerStyle,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
              Positioned(
                right: -SmartViewTableMetrics.padX + AppSpacing.xxs / 2,
                child: AnimatedOpacity(
                  opacity: sortState == null ? 0 : 1,
                  duration: AppDurations.smartChip,
                  child: SvSortArrow(
                    isAscending: sortState ?? true,
                    color: AppColors.white,
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
    required this.cutCells,
    required this.metrics,
    required this.height,
    required this.isBand,
    required this.onTap,
    this.onOpenFiles,
  });

  final SvFileOpener? onOpenFiles;
  final bool isBand;
  final SmartViewColumns columns;
  final SvRow row;

  /// The shortened text of a cell that was cut, else null.
  final List<String?> cutCells;
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
          decoration: BoxDecoration(
            color: isBand ? AppSv.tableRowAlt : AppColors.white,
            border: const Border(bottom: BorderSide(color: AppSv.hairline)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: cells[i].isEmpty
                      ? null
                      : () => SvCellDetailsSheet.show(
                          context,
                          label: columns.columns[i].label,
                          value: cells[i].text,
                        ),
                  child: Container(
                    width: metrics.widths[i],
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: SmartViewTableMetrics.padX,
                    ),
                    child: _Cell(
                      column: columns.columns[i],
                      cell: cells[i],
                      cut: cutCells[i],
                      onOpenFiles: onOpenFiles,
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

/// One cell: a pill, or one line of text (never wrapped); a cut text is
/// followed by "View more" on the same line.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.column,
    required this.cell,
    required this.cut,
    this.onOpenFiles,
  });

  final SvFileOpener? onOpenFiles;
  final SvColumn column;
  final SvCellValue cell;
  final String? cut;

  @override
  Widget build(BuildContext context) {
    if (column.type == SvColType.status && !cell.isEmpty) {
      return SmartViewStatusPill(label: cell.text, isCompact: true);
    }
    if (column.type == SvColType.file && cell.files.isNotEmpty) {
      return SvFileTableCell(files: cell.files, onOpen: onOpenFiles);
    }
    final style = cell.isEmpty
        ? SmartViewTableMetrics.cellStyle.copyWith(color: AppColors.cardMuted)
        : SmartViewTableMetrics.cellStyleOf(column);
    final shown = cut;
    if (shown == null) {
      return Text(
        cell.text,
        style: style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
      );
    }
    return Row(
      children: [
        Flexible(
          child: Text(
            shown,
            style: style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          ),
        ),
        const SizedBox(width: AppSv.tableMoreGap),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => SvCellDetailsSheet.show(
            context,
            label: column.label,
            value: cell.text,
          ),
          child: const Text(
            SmartViewTableMetrics.moreLabel,
            style: AppSv.tableMore,
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ],
    );
  }
}
