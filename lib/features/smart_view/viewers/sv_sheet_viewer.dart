import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../data/smart_view/preview/sv_preview_parsers.dart';

/// A spreadsheet (xlsx, csv, tsv) as a read-only table: sheet tabs on top
/// (when there are several), a header row of column letters, a row-number
/// column, horizontal and vertical scroll, one-line cells that open in a sheet
/// on tap, and a footer note when rows or columns were left out. Values are
/// shown as plain text only.
class SvSheetViewer extends StatefulWidget {
  const SvSheetViewer({super.key, required this.book});

  final SvSheetBook book;

  /// "A", "B", ... "Z", "AA" for the zero-based [index].
  static String letters(int index) {
    var n = index + 1;
    final out = StringBuffer();
    final chars = <String>[];
    while (n > 0) {
      final r = (n - 1) % 26;
      chars.add(String.fromCharCode(0x41 + r));
      n = (n - 1) ~/ 26;
    }
    for (final c in chars.reversed) {
      out.write(c);
    }
    return out.toString();
  }

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
    final width = AppSv.fileSheetNumber + cols * AppSv.fileSheetCell;
    return Column(
      children: [
        if (tables.length > 1)
          SizedBox(
            height:
                AppSv.fileSheetTab * scale.clamp(1, 1.6) + AppSpacing.sm * 2,
            child: ListView.separated(
              key: const ValueKey('sv-sheet-tabs'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(AppSpacing.sm),
              itemCount: tables.length,
              separatorBuilder: (context, i) =>
                  const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, i) => Semantics(
                button: true,
                selected: i == _tab,
                label: 'Sheet ${tables[i].name}',
                excludeSemantics: true,
                child: GestureDetector(
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
          ),
        Expanded(
          child: table.rows.isEmpty
              ? const Center(
                  child: Text(
                    'This sheet is empty',
                    key: ValueKey('sv-sheet-empty'),
                    style: AppText.supporting,
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        _Row(
                          label: '',
                          cells: [
                            for (var c = 0; c < cols; c++)
                              SvSheetViewer.letters(c),
                          ],
                          cols: cols,
                          height: rowH,
                          isHeader: true,
                        ),
                        Expanded(
                          child: ListView.builder(
                            key: const ValueKey('sv-sheet-rows'),
                            itemExtent: rowH,
                            itemCount: table.rows.length,
                            itemBuilder: (context, i) => _Row(
                              label: '${i + 1}',
                              cells: table.rows[i],
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
        if (table.isCut)
          Container(
            key: const ValueKey('sv-sheet-notice'),
            width: double.infinity,
            color: AppColors.violetTint,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              "Showing the first ${table.rows.length} rows and $cols columns "
              "of '${table.name}'",
              style: AppText.supporting,
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.cells,
    required this.cols,
    required this.height,
    required this.isHeader,
  });

  final String label;
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
        Container(
          width: AppSv.fileSheetNumber,
          height: height,
          alignment: Alignment.center,
          color: AppColors.surfaceSubtle,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: AppSv.fileChipSize,
          ),
        ),
        for (var c = 0; c < cols; c++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final text = c < cells.length ? cells[c] : '';
              if (isHeader || text.isEmpty) return;
              AppBottomSheet.show<void>(
                context,
                title: 'Cell',
                child: SelectableText(text, style: AppText.readable),
              );
            },
            child: Container(
              width: AppSv.fileSheetCell,
              height: height,
              alignment: isHeader ? Alignment.center : Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                c < cells.length
                    ? cells[c].replaceAll(RegExp(r'\s+'), ' ')
                    : '',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: isHeader
                    ? AppSv.fileChipName
                    : AppSv.fileChipSize.copyWith(
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
