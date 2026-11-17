import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_state_view.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/repositories/smart_view_repository.dart';
import '../smart_view_controller.dart';

/// The drawer of the Smart view tab: a Find box over the list of structures,
/// the open one as a long violet pill. Selecting one closes the drawer.
class SmartViewDrawer extends StatelessWidget {
  const SmartViewDrawer({super.key, required this.controller});

  final SmartViewController controller;

  static const emptyTitle = 'No smart views yet';

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SafeArea(
      right: false,
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.md,
              AppSpacing.page,
              AppSpacing.xs,
            ),
            child: Text('Smart view', style: AppText.title),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.xs,
            ),
            child: AppTextField(
              controller: c.findField,
              hint: 'Find',
              minHeight: AppSpacing.searchHeight,
              fillColor: AppColors.searchFill,
              borderColor: Colors.transparent,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadius.xs),
              ),
              leading: const Icon(
                Icons.search,
                size: 18,
                color: AppColors.muted,
              ),
              suffix: Obx(
                () => c.find.value.isEmpty
                    ? const SizedBox.shrink()
                    : AppButton.icon(
                        icon: Icons.close,
                        semanticLabel: 'Clear',
                        onPressed: () {
                          c.findField.clear();
                          c.find.value = '';
                        },
                      ),
              ),
              onChanged: (v) => c.find.value = v,
            ),
          ),
          Expanded(child: _List(controller: c)),
        ],
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller});

  final SmartViewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final phase = c.listPhase.value;
      final state = switch (phase) {
        SvPhase.loading => AppViewState.loading,
        SvPhase.error => AppViewState.error,
        SvPhase.offline => AppViewState.offline,
        SvPhase.empty => AppViewState.empty,
        _ => AppViewState.content,
      };
      return AppStateView(
        state: state,
        emptyTitle: SmartViewDrawer.emptyTitle,
        errorMessage: 'The list could not be loaded.',
        onRetry: () => c.loadList(isForced: true),
        child: _Rows(controller: c),
      );
    });
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.controller});

  final SmartViewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final shown = c.shownSources;
      final openName = c.current.value?.name;
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.lg,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              0,
              AppSpacing.xs,
              AppSpacing.xxs,
            ),
            child: Row(
              children: [
                const Text('STRUCTURES', style: AppText.eyebrow),
                const SizedBox(width: AppSpacing.xs),
                Text('${shown.length}', style: AppText.caption),
              ],
            ),
          ),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: Text('Nothing matches.', style: AppText.readable),
              ),
            ),
          for (final s in shown)
            _DrawerRow(
              key: ValueKey('sv-drawer-${s.name}'),
              title: s.caption,
              isSelected: s.name == openName,
              onTap: () => c.show(s),
            ),
        ],
      );
    });
  }
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    super.key,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: title,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.drawerRowHeight,
          ),
          margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.violetTint : Colors.transparent,
            borderRadius: AppRadius.pillAll,
          ),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.rowTitle.copyWith(
              color: isSelected ? AppColors.violetStrong : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
