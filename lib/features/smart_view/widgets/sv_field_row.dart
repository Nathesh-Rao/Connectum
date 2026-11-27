import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';

/// One line of a field checklist (Group by, Columns): the caption, the muted
/// technical name under it and, on the right, a number badge (group level)
/// or a tick, and optionally a drag handle.
class SvFieldRow extends StatelessWidget {
  const SvFieldRow({
    super.key,
    required this.label,
    required this.name,
    required this.isTicked,
    required this.onTap,
    this.level,
    this.dragIndex,
  });

  final String label;
  final String name;
  final bool isTicked;
  final VoidCallback onTap;

  /// 1-based group level shown as a badge when ticked.
  final int? level;

  /// When set, a drag handle for a [ReorderableListView] at this index.
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isTicked,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.smartChip,
          constraints: const BoxConstraints(minHeight: AppSv.sheetRowHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: isTicked ? AppColors.violetTint : Colors.transparent,
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isTicked
                            ? AppColors.violetStrong
                            : AppColors.ink,
                      ),
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: AppColors.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (level != null)
                Container(
                  width: AppSv.orderBadge,
                  height: AppSv.orderBadge,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.violet,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$level',
                    style: AppText.caption.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                )
              else if (isTicked)
                const Icon(
                  Icons.check,
                  size: AppSpacing.popupMenuIcon,
                  color: AppColors.violetStrong,
                ),
              if (dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex!,
                  child: const Padding(
                    padding: EdgeInsets.only(left: AppSpacing.sm),
                    child: Icon(
                      Icons.drag_handle,
                      size: AppSpacing.popupMenuIcon,
                      color: AppColors.tertiary,
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
