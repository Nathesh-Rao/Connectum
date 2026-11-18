import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/smart_view/sv_columns.dart';
import '../smart_view_controller.dart';
import 'sv_col_icon.dart';

/// The sort sheet: the fields a view can be sorted by, a direction arrow on
/// the one in use. Tapping a field sorts by it (ascending); tapping the
/// active field or its arrow turns the direction.
class SvSortSheet {
  SvSortSheet._();

  static Future<void> show(BuildContext context, SmartViewController c) {
    return AppBottomSheet.show<void>(
      context,
      title: 'Sort',
      child: SvSortList(
        controller: c,
        onPicked: () => Navigator.maybePop(context),
      ),
    );
  }
}

class SvSortList extends StatelessWidget {
  const SvSortList({super.key, required this.controller, this.onPicked});

  final SmartViewController controller;
  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final cols = [
      for (final col in c.columns?.columns ?? const <SvColumn>[])
        if (col.type != SvColType.file) col,
    ];
    return Obx(() {
      final q = c.query.value;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final col in cols)
                  _SortRow(
                    column: col,
                    isSelected: q.sortKey == col.key,
                    isAscending: q.isAscending,
                    onTap: () {
                      if (q.sortKey == col.key) {
                        c.flipSort();
                      } else {
                        c.setSort(col.key, isAscending: true);
                        onPicked?.call();
                      }
                    },
                    onFlip: c.flipSort,
                  ),
              ],
            ),
          ),
          if (q.isSorting)
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton.text(
                label: 'Remove sort',
                onPressed: () {
                  c.clearSort();
                  onPicked?.call();
                },
              ),
            ),
        ],
      );
    });
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.column,
    required this.isSelected,
    required this.isAscending,
    required this.onTap,
    required this.onFlip,
  });

  final SvColumn column;
  final bool isSelected;
  final bool isAscending;
  final VoidCallback onTap;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Sort by ${column.label}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.smartChip,
          constraints: const BoxConstraints(minHeight: AppSv.sheetRowHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.violetTint : Colors.transparent,
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            children: [
              Container(
                width: AppSv.sheetIconCircle,
                height: AppSv.sheetIconCircle,
                decoration: const BoxDecoration(
                  color: AppSv.sortIconFill,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  SvColIcon.of(column.type),
                  size: AppSpacing.popupMenuIcon,
                  color: isSelected ? AppColors.violetStrong : AppColors.muted,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  column.label,
                  style: AppText.body.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.violetStrong : AppColors.ink,
                  ),
                ),
              ),
              if (isSelected)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onFlip,
                  child: SvSortArrow(
                    isAscending: isAscending,
                    color: AppColors.violetStrong,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An up arrow that turns half a circle when the order is descending.
class SvSortArrow extends StatelessWidget {
  const SvSortArrow({
    super.key,
    required this.isAscending,
    required this.color,
    this.size = AppSpacing.popupMenuIcon,
  });

  final bool isAscending;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: isAscending ? 0 : 0.5,
      duration: AppDurations.smartChip,
      curve: AppCurves.out,
      child: Icon(Icons.arrow_upward, size: size, color: color),
    );
  }
}
