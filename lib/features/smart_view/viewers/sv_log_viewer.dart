import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sv.dart';
import '../../log_viewer/models/log_document.dart';

/// The text-file variant of the Smart View preview for the app's own log:
/// monospace and selectable like [SvTextViewer], but one lazily built row per
/// text row, all of one height, so a 10 MB file stays smooth and jumps are
/// exact. Wrapped lines are cut at the width in characters. Error and warning
/// entries are tinted, the header and separators are muted, search matches
/// are highlighted.
class SvLogViewer extends StatefulWidget {
  const SvLogViewer({
    super.key,
    required this.doc,
    required this.scroll,
    required this.isWrap,
    required this.fontSize,
    required this.hitStarts,
    required this.queryLength,
    required this.onRows,
    required this.onTop,
    required this.onLatest,
    this.currentHit,
  });

  static const pad = AppSv.fileTextPad;

  /// Width of one monospace character as a share of the font size.
  static const charWidth = 0.62;

  final LogDocument doc;
  final ScrollController scroll;
  final bool isWrap;
  final double fontSize;
  final Map<int, List<int>> hitStarts;
  final int queryLength;
  final LogHit? currentHit;

  /// Reports the row layout (and the height of a row) after each build.
  final void Function(LogRowIndex rows, double extent) onRows;
  final VoidCallback onTop;
  final VoidCallback onLatest;

  @override
  State<SvLogViewer> createState() => _SvLogViewerState();
}

class _SvLogViewerState extends State<SvLogViewer> {
  LogRowIndex? _rows;

  LogRowIndex _indexFor(int charsPerRow) {
    final r = _rows;
    if (r != null &&
        identical(r.doc, widget.doc) &&
        r.charsPerRow == charsPerRow) {
      return r;
    }
    return _rows = LogRowIndex(widget.doc, charsPerRow);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final scaled = MediaQuery.textScalerOf(context).scale(w.fontSize);
    final style = AppSv.fileMono.copyWith(fontSize: w.fontSize);
    final extent = scaled * (AppSv.fileMono.height ?? 1.4);
    final charW = scaled * SvLogViewer.charWidth;
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final perRow = w.isWrap
                ? math.max(
                    8,
                    ((box.maxWidth - 2 * SvLogViewer.pad) / charW).floor(),
                  )
                : 0;
            final rows = _indexFor(perRow);
            w.onRows(rows, extent);
            final list = SelectionArea(
              child: ListView.builder(
                key: const ValueKey('log-lines'),
                controller: w.scroll,
                itemCount: rows.rowCount,
                itemExtent: extent,
                itemBuilder: (context, row) => _row(rows, row, style),
              ),
            );
            if (w.isWrap) return list;
            final width = math.max(
              box.maxWidth,
              charW * (w.doc.longest + 2) + 2 * SvLogViewer.pad,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: width, child: list),
            );
          },
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Jump(
                key: const ValueKey('log-jump-top'),
                icon: Icons.vertical_align_top,
                label: 'Jump to top',
                onTap: w.onTop,
              ),
              const SizedBox(height: 8),
              _Jump(
                key: const ValueKey('log-jump-latest'),
                icon: Icons.vertical_align_bottom,
                label: 'Jump to latest',
                onTap: w.onLatest,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(LogRowIndex rows, int row, TextStyle style) {
    final doc = widget.doc;
    final line = rows.lineOf(row);
    final (from, to) = rows.rangeOf(row, line);
    final text = to <= from ? ' ' : doc.lines[line].substring(from, to);
    final kind = doc.kindOf(line);
    final color = switch (kind) {
      LogLineKind.error => AppColors.error.withValues(alpha: 0.08),
      LogLineKind.warning => AppColors.violetTint,
      _ => null,
    };
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: SvLogViewer.pad),
      alignment: Alignment.centerLeft,
      child: Text.rich(
        _spans(line, text, from, kind == LogLineKind.muted),
        style: style,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.clip,
      ),
    );
  }

  TextSpan _spans(int line, String text, int from, bool isMuted) {
    final base = TextStyle(color: isMuted ? AppColors.muted : null);
    final starts = widget.hitStarts[line];
    final len = widget.queryLength;
    if (starts == null || len == 0) return TextSpan(text: text, style: base);
    final hit = widget.currentHit;
    final children = <TextSpan>[];
    var at = 0;
    for (final s in starts) {
      final a = math.max(s - from, at);
      final b = math.min(s + len - from, text.length);
      if (b <= a) continue;
      if (a > at) children.add(TextSpan(text: text.substring(at, a)));
      final isCurrent = hit != null && hit.line == line && hit.start == s;
      children.add(
        TextSpan(
          text: text.substring(a, b),
          style: TextStyle(
            backgroundColor: isCurrent
                ? AppColors.primaryBorder
                : AppColors.primaryTint,
            color: AppColors.ink,
          ),
        ),
      );
      at = b;
    }
    if (at < text.length) children.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: base, children: children);
  }
}

class _Jump extends StatelessWidget {
  const _Jump({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.white,
    shape: const CircleBorder(side: BorderSide(color: AppSv.cardBorder)),
    child: IconButton(
      tooltip: label,
      icon: Icon(icon, color: AppColors.ink),
      onPressed: onTap,
    ),
  );
}
