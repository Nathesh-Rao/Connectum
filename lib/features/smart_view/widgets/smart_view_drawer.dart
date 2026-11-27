import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/tour/tour_texts.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_tag.dart';
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

  /// The one left/right inset of the title, Find, STRUCTURES and the rows.
  static const inset = AppSpacing.md;

  /// Where a row's label starts inside its pill: the Find field's own side
  /// padding plus its 1 dp border, so labels sit under the search icon.
  static const rowTextInset = AppSpacing.controlPaddingX + 1;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return KeyedSubtree(
      key: c.tour?.drawerKey,
      child: SafeArea(
        right: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                SmartViewDrawer.inset,
                AppSpacing.md,
                SmartViewDrawer.inset,
                AppSpacing.xs,
              ),
              child: Text('Smart view', style: AppText.title),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SmartViewDrawer.inset,
                0,
                SmartViewDrawer.inset,
                AppSpacing.xs,
              ),
              child: AppTextField(
                controller: c.findField,
                hint: 'Find',
                minHeight: AppSpacing.searchHeight,
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
      final phase = c.drawerPhase;
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
        onRetry: c.reload,
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
          SmartViewDrawer.inset,
          AppSpacing.xs,
          SmartViewDrawer.inset,
          AppSpacing.lg,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
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
          for (final (i, s) in shown.indexed)
            KeyedSubtree(
              key: (openName == null ? i == 0 : s.name == openName)
                  ? c.tour?.rowKey
                  : null,
              child: _DrawerRow(
                key: ValueKey('sv-drawer-${s.name}'),
                title: s.caption,
                isSelected: s.name == openName,
                isSample: c.tour?.demo.isSampleSource(s) ?? false,
                onTap: () => c.show(s),
              ),
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
    this.isSample = false,
  });

  final String title;
  final bool isSelected;
  final bool isSample;
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
          padding: const EdgeInsets.symmetric(
            horizontal: SmartViewDrawer.rowTextInset,
          ),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.violetTint : Colors.transparent,
            borderRadius: AppRadius.pillAll,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.rowTitle.copyWith(
                    color: isSelected ? AppColors.violetStrong : AppColors.ink,
                  ),
                ),
              ),
              if (isSample)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.xs),
                  child: AppTag(
                    label: TourTexts.sampleTag,
                    tone: AppTagTone.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
