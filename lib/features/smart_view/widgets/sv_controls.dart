import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_popup_menu.dart';
import '../../../core/widgets/app_text_field.dart';
import '../smart_view_controller.dart';
import 'smart_view_mode_switch.dart';
import 'sv_col_icon.dart';
import 'sv_filter_sheet.dart';
import 'sv_pill.dart';
import 'sv_sort_sheet.dart';

/// The row under the header: the Cards/Table switch on the left, Search,
/// Filter and Sort on the right. Search opens as a field laid over the whole
/// row, growing from the right edge.
class SvControls extends StatelessWidget {
  const SvControls({super.key, required this.controller});

  final SmartViewController controller;

  static const allFields = 'All fields';

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xxs,
        AppSpacing.xs,
        AppSpacing.xxs,
      ),
      child: SizedBox(
        height: AppSpacing.badgedIconHit,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            alignment: Alignment.centerRight,
            children: [
              Row(
                children: [
                  Obx(
                    () => SmartViewModeSwitch(
                      mode: c.mode.value,
                      onChanged: c.setMode,
                    ),
                  ),
                  const Spacer(),
                  SvIconAction(
                    icon: Icons.search,
                    label: 'Search',
                    onTap: c.openSearch,
                  ),
                  Obx(
                    () => SvIconAction(
                      icon: Icons.filter_list,
                      label: 'Filter',
                      badge: c.query.value.activeConditions.length,
                      isActive: c.query.value.activeConditions.isNotEmpty,
                      onTap: () => SvFilterSheet.show(context, c),
                    ),
                  ),
                  Obx(
                    () => SvIconAction(
                      icon: Icons.swap_vert,
                      label: 'Sort',
                      isActive: c.query.value.isSorting,
                      onTap: () => SvSortSheet.show(context, c),
                    ),
                  ),
                ],
              ),
              Obx(
                () => _SearchOverlay(
                  controller: c,
                  isOpen: c.isSearchOpen.value,
                  width: box.maxWidth,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchOverlay extends StatelessWidget {
  const _SearchOverlay({
    required this.controller,
    required this.isOpen,
    required this.width,
  });

  final SmartViewController controller;
  final bool isOpen;
  final double width;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: isOpen ? width : 0),
      duration: AppDurations.smartControls,
      curve: AppCurves.out,
      builder: (context, w, _) {
        if (w <= 0 && !isOpen) return const SizedBox.shrink();
        return ClipRect(
          child: SizedBox(
            width: w,
            height: AppSpacing.badgedIconHit,
            child: OverflowBox(
              alignment: Alignment.centerRight,
              minWidth: 0,
              maxWidth: width,
              child: SizedBox(
                width: width,
                child: ColoredBox(
                  color: AppColors.white,
                  child: _SearchBar(controller: controller),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});

  final SmartViewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: c.searchField,
            builder: (context, value, _) => AppTextField(
              controller: c.searchField,
              hint: 'Search',
              autofocus: true,
              hasFocusRing: false,
              minHeight: AppSpacing.pillTall + 2,
              borderRadius: AppRadius.pillAll,
              borderColor: Colors.transparent,
              fillColor: AppColors.searchFill,
              horizontalPadding: AppSpacing.sm,
              textStyle: AppText.body,
              textInputAction: TextInputAction.search,
              onChanged: c.onSearchTyped,
              leading: const Icon(
                Icons.search,
                size: AppSpacing.popupMenuIcon,
                color: AppColors.muted,
              ),
              suffix: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.cancel,
                        size: AppSpacing.popupMenuIcon,
                        color: AppColors.tertiary,
                      ),
                      onPressed: c.clearSearchText,
                    ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Obx(() {
          final q = c.query.value;
          final cols = c.columns?.columns;
          final scoped = q.scope == null
              ? null
              : cols?.where((x) => x.key == q.scope).firstOrNull;
          return Builder(
            builder: (anchor) => SvPill(
              label: scoped?.label ?? SvControls.allFields,
              isActive: scoped != null,
              maxWidth: 124,
              onTap: () => _scopeMenu(anchor, c),
            ),
          );
        }),
        SvIconAction(
          icon: Icons.close,
          label: 'Close search',
          onTap: c.closeSearch,
        ),
      ],
    );
  }

  static void _scopeMenu(BuildContext anchor, SmartViewController c) {
    final cols = c.columns?.columns ?? const [];
    final current = c.query.value.scope;
    AppPopupMenuCard.show(anchor, [
      AppMenuItem(
        icon: current == null ? Icons.check : Icons.search,
        label: SvControls.allFields,
        onTap: () => c.setScope(null),
      ),
      for (final col in cols)
        AppMenuItem(
          icon: current == col.key ? Icons.check : SvColIcon.of(col.type),
          label: col.label,
          onTap: () => c.setScope(col.key),
        ),
    ]);
  }
}
