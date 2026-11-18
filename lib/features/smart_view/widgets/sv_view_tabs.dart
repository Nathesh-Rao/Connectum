import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_spinner.dart';
import '../smart_view_controller.dart';
import 'sv_manage_view_sheet.dart';
import 'sv_save_view_sheet.dart';

/// The strip under the controls: Default View, the saved views of this
/// structure, then "+" (save the current state as a view). A saved view
/// that was changed shows "Unsaved changes" with Save and Reset.
class SvViewTabs extends StatelessWidget {
  const SvViewTabs({super.key, required this.controller});

  final SmartViewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.views == null) return const SizedBox.shrink();
    return Obx(() {
      final phase = c.viewsPhase.value;
      final selected = c.selectedViewId.value;
      final isSaving = c.isSavingViews.value;
      final canManage = c.canManage;
      final isDirty = c.isDirty;
      final tabs = c.tabs.toList();
      final shared = c.sharedTabs.toList();
      return SizedBox(
        height: AppSv.viewTabHeight + AppSpacing.xs * 2,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              _Tab(
                label: 'Default View',
                isSelected: selected == null,
                isBusy: isSaving && selected == null,
                onTap: () => c.selectView(null),
              ),
              if (phase == SvViewsPhase.loading)
                for (var i = 0; i < 3; i++) const _SkeletonTab(),
              if (phase == SvViewsPhase.error)
                _Tab(
                  label: "Views didn't load · Retry",
                  isSelected: false,
                  onTap: c.retryViews,
                ),
              if (phase == SvViewsPhase.ready) ...[
                for (final v in tabs)
                  _Tab(
                    label: v.name,
                    isSelected: selected == v.id,
                    isBusy: isSaving && selected == v.id,
                    onTap: () => c.selectView(v.id),
                    onLong: canManage
                        ? () => SvManageViewSheet.show(context, c, v)
                        : null,
                  ),
                for (final v in shared)
                  _Tab(
                    label: v.name,
                    icon: Icons.group_outlined,
                    isSelected: selected == v.id,
                    onTap: () => c.selectView(v.id),
                  ),
                if (canManage)
                  _Tab(
                    label: '+',
                    semantic: 'Save as new view',
                    isSelected: false,
                    onTap: () => SvSaveViewSheet.show(context, c),
                  ),
              ],
              if (isDirty && phase != SvViewsPhase.loading)
                _DirtyPill(controller: c, canSave: c.canSave),
            ],
          ),
        ),
      );
    });
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.onLong,
    this.icon,
    this.isBusy = false,
    this.semantic,
  });

  final String label;
  final bool isSelected;
  final bool isBusy;
  final IconData? icon;
  final String? semantic;
  final VoidCallback onTap;
  final VoidCallback? onLong;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.white : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.only(right: AppSv.viewTabGap),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: semantic ?? label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: onLong,
          child: AnimatedContainer(
            duration: AppDurations.smartChip,
            height: AppSv.viewTabHeight,
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.fill,
              borderRadius: AppRadius.pillAll,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: AppSpacing.pillChevron, color: color),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.readableStrong.copyWith(color: color),
                  ),
                ),
                if (isBusy) ...[
                  const SizedBox(width: AppSpacing.xs),
                  const AppSpinner(size: AppSpinnerSize.xs),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonTab extends StatelessWidget {
  const _SkeletonTab();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSv.viewTabGap),
      child: Container(
        width: 84,
        height: AppSv.viewTabHeight,
        decoration: const BoxDecoration(
          color: AppColors.fill,
          borderRadius: AppRadius.pillAll,
        ),
      ),
    );
  }
}

class _DirtyPill extends StatelessWidget {
  const _DirtyPill({required this.controller, required this.canSave});

  final SmartViewController controller;
  final bool canSave;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      height: AppSv.viewTabHeight,
      padding: const EdgeInsets.only(left: AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.violetTint,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Unsaved changes',
            style: AppText.readableStrong.copyWith(
              color: AppColors.violetStrong,
            ),
          ),
          if (canSave) _PillAction(label: 'Save', onTap: c.saveCurrent),
          _PillAction(label: 'Reset', onTap: c.resetToSaved),
        ],
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Center(
            child: Text(
              label,
              style: AppText.readableStrong.copyWith(color: AppColors.primary),
            ),
          ),
        ),
      ),
    );
  }
}
