import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_state_image.dart';
import '../../../core/widgets/app_state_view.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/form_option.dart';
import '../forms_picker_controller.dart';

/// The forms button's sheet, as the prototype has it: a search field, Recent,
/// then every form and My Submissions last.
class FormsPickerSheet extends StatelessWidget {
  const FormsPickerSheet({super.key, required this.controller});

  final FormsPickerController controller;

  static Future<void> show(
    BuildContext context,
    FormsPickerController controller,
  ) {
    controller.prepare();
    return AppBottomSheet.show<void>(
      context,
      title: 'Forms',
      child: FormsPickerSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyGeneric,
      AppStateImageKind.error,
      AppStateImageKind.offline,
      AppStateImageKind.noResults,
    ], size: AppSpacing.stateImageSmall);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: c.queryField,
          hint: 'Search forms',
          minHeight: AppSpacing.searchHeight,
          fillColor: AppColors.surface,
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
          leading: const Icon(Icons.search, size: 18, color: AppColors.muted),
          textInputAction: TextInputAction.search,
          onChanged: (v) => c.query.value = v,
        ),
        const SizedBox(height: AppSpacing.sm),
        Obx(() {
          final state = c.viewState;
          if (state != AppViewState.content) {
            return SizedBox(
              height: 300,
              child: AppStateView(
                state: state,
                emptyTitle: 'No forms for you yet',
                emptyMessage: 'Forms you can fill show up here.',
                errorMessage: "We couldn't load your forms.",
                onRetry: c.options.refresh,
                loadingChild: const _Skeleton(),
                child: const SizedBox.shrink(),
              ),
            );
          }
          return _List(controller: c);
        }),
      ],
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller});

  final FormsPickerController controller;

  @override
  Widget build(BuildContext context) => Obx(() => _content(context));

  Widget _content(BuildContext context) {
    final c = controller;
    final isSearching = c.query.value.trim().isNotEmpty;
    final recents = isSearching ? const [] : c.recents;
    final shown = c.shown;
    final hasNothing = shown.isEmpty && !c.showsMySubmissions;
    if (hasNothing) {
      return const SizedBox(
        height: 320,
        child: AppStateView(
          state: AppViewState.noResults,
          emptyTitle: 'No forms match',
          emptyMessage: 'Try another word.',
          child: SizedBox.shrink(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recents.isNotEmpty) ...[
          const _Label('Recent'),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final r in recents)
                _RecentChip(
                  label: r.caption.isEmpty ? r.name : r.caption,
                  onTap: () {
                    Navigator.of(context).pop();
                    c.openRecent(r);
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (!isSearching && shown.isNotEmpty) const _Label('All forms'),
        for (final o in shown) _OptionRow(controller: c, option: o),
        if (c.showsMySubmissions)
          AppListRow(
            title: 'My Submissions',
            minHeight: AppSpacing.settingRowHeight,
            titleStyle: AppText.rowTitle,
            leading: const Icon(
              Icons.history,
              size: 18,
              color: AppColors.muted,
            ),
            trailing: const _Chevron(),
            onTap: () {
              Navigator.of(context).pop();
              c.openMySubmissions();
            },
          ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.controller, required this.option});

  final FormsPickerController controller;
  final FormOption option;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final isAvailable = c.isAvailable(option);
    final row = AppListRow(
      title: option.caption,
      subtitle: isAvailable ? null : "Isn't available on mobile yet",
      minHeight: AppSpacing.settingRowHeight,
      leading: Icon(c.iconOf(option), size: 18, color: AppColors.muted),
      trailing: isAvailable ? const _Chevron() : null,
      onTap: isAvailable
          ? () {
              Navigator.of(context).pop();
              c.open(option);
            }
          : null,
    );
    return isAvailable ? row : Opacity(opacity: 0.55, child: row);
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) =>
      const Icon(Icons.chevron_right, size: 20, color: AppColors.rowChevron);
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Text(
      text.toUpperCase(),
      style: AppText.eyebrow.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Open $label',
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.line),
          borderRadius: AppRadius.pillAll,
        ),
        child: Center(
          widthFactor: 1,
          child: Text(label, style: AppText.readable),
        ),
      ),
    ),
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => AppSkeletonScope(
    child: Column(
      children: [
        for (var i = 0; i < 5; i++)
          SizedBox(
            height: AppSpacing.settingRowHeight,
            child: Row(
              children: [
                const AppSkeleton(width: 18, height: 18),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.4 + (i % 3) * 0.15,
                    child: const AppSkeleton(height: AppSpacing.sm),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
