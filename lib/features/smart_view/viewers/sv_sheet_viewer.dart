import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../data/smart_view/preview/sv_preview_parsers.dart';

/// A spreadsheet as a table: sheet tabs on top (when there are several), the
/// first row as a sticky header, horizontal and vertical scroll, one-line
/// cells that open in a sheet on tap. Capped at 500 rows by 50 columns, with a
/// notice when the file has more.
class SvSheetViewer extends StatefulWidget {
  const SvSheetViewer({super.key, required this.book});

  final SvSheetBook book;

  @override
  State<SvSheetViewer> createState() => _SvSheetViewerState();
}

class _SvSheetViewerState extends State<SvSheetViewer> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final tables = widget.book.tables;
    final table = tables[_tab.clamp(0, tables.length - 1)];
    final cols = table.columns;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final rowH = AppSv.fileSheetRow * scale.clamp(1, 1.6);
    final width = cols * AppSv.fileSheetCell;
    return Column(
      children: [
        if (tables.length > 1)
          SizedBox(
            height: AppSv.fileSheetTab + AppSpacing.sm * 2,
            child: ListView.separated(
              key: const ValueKey('sv-sheet-tabs'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(AppSpacing.sm),
              itemCount: tables.length,
              separatorBuilder: (context, i) =>
                  const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: i == _tab
                        ? AppColors.violetTint
                        : AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    tables[i].name,
                    style: AppSv.fileChipName.copyWith(
                      color: i == _tab
                          ? AppColors.violetStrong
                          : AppColors.cardMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (table.isCut)
          Container(
            key: const ValueKey('sv-sheet-notice'),
            width: double.infinity,
            color: AppColors.violetTint,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: const Text(
              'Showing first 500 rows — Download for the full file',
              style: AppText.supporting,
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width < 1 ? 1 : width,
              child: Column(
                children: [
                  if (table.rows.isNotEmpty)
                    _Row(
                      cells: table.rows.first,
                      cols: cols,
                      height: rowH,
                      isHeader: true,
                    ),
                  Expanded(
                    child: ListView.builder(
                      key: const ValueKey('sv-sheet-rows'),
                      itemExtent: rowH,
                      itemCount: table.rows.length - 1 < 0
                          ? 0
                          : table.rows.length - 1,
                      itemBuilder: (context, i) => _Row(
                        cells: table.rows[i + 1],
                        cols: cols,
                        height: rowH,
                        isHeader: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.cells,
    required this.cols,
    required this.height,
    required this.isHeader,
  });

  final List<String> cells;
  final int cols;
  final double height;
  final bool isHeader;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: isHeader ? AppColors.surfaceSubtle : AppColors.white,
      border: const Border(bottom: BorderSide(color: AppSv.hairline)),
    ),
    child: Row(
      children: [
        for (var c = 0; c < cols; c++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final text = c < cells.length ? cells[c] : '';
              if (text.isEmpty) return;
              AppBottomSheet.show<void>(
                context,
                title: 'Cell',
                child: SelectableText(text, style: AppText.readable),
              );
            },
            child: Container(
              width: AppSv.fileSheetCell,
              height: height,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                c < cells.length ? cells[c].replaceAll(RegExp(r'\s+'), ' ') : '',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: isHeader ? AppSv.fileChipName : AppSv.fileChipSize.copyWith(
                  fontSize: 12,
                  color: AppSv.cardInk,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
